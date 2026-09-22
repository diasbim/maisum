#!/usr/bin/env node
/**
 * Drives the MaisUm Flutter app on an Android emulator, over adb.
 *
 * Flutter paints to a canvas, so `uiautomator dump` returns no text and
 * nothing can be found by label — every handle here is a coordinate. Two
 * things make that survivable:
 *
 *   - Coordinates are fractions of the screen, not pixels, so a different
 *     AVD than the one this was written against still lands on the target.
 *   - Every tap waits for the screen to stop changing before it returns,
 *     by hashing screencaps until two in a row match. This is the whole
 *     reason the driver exists: taps sent on a fixed sleep get swallowed by
 *     route transitions, which silently drops digits out of a PIN and
 *     spills typed text into whichever field had focus a moment ago.
 *
 * Usage:  node .claude/skills/run-maisum/driver.mjs <command> [args]
 * Run with no arguments for the command list.
 */

import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..', '..', '..');
const CAPTURAS = join(AQUI, 'shots');
const PACOTE = 'com.tsintsivadigital.maisum';
const PROJETO = 'loyaltyos-fc4dd';
const AVD = 'Medium_Phone';

/* ------------------------------------------------------------------- o adb */

function acharAdb() {
  if (process.env.ADB) return process.env.ADB;
  const candidatos = [
    process.env.ANDROID_HOME && join(process.env.ANDROID_HOME, 'platform-tools', 'adb.exe'),
    process.env.ANDROID_HOME && join(process.env.ANDROID_HOME, 'platform-tools', 'adb'),
    process.env.LOCALAPPDATA && join(process.env.LOCALAPPDATA, 'Android', 'Sdk', 'platform-tools', 'adb.exe'),
    process.env.HOME && join(process.env.HOME, 'Android', 'Sdk', 'platform-tools', 'adb'),
    process.env.HOME && join(process.env.HOME, 'Library', 'Android', 'sdk', 'platform-tools', 'adb'),
  ].filter(Boolean);
  for (const c of candidatos) if (existsSync(c)) return c;
  return 'adb'; // no PATH, com sorte
}

const ADB = acharAdb();
const SERIE = process.env.ANDROID_SERIAL || 'emulator-5554';

function adb(args, opcoes = {}) {
  return execFileSync(ADB, ['-s', SERIE, ...args], {
    encoding: opcoes.binario ? 'buffer' : 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    stdio: ['ignore', 'pipe', opcoes.silencioso ? 'ignore' : 'inherit'],
    ...opcoes.extra,
  });
}

const shell = (linha) => adb(['shell', linha]);
const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

/* ------------------------------------------------------- esperar e observar */

/**
 * Clears Android's "isn't responding" dialog, which this app earns on its own.
 *
 * The WorkManager background worker does not answer `onStartJob`, so a cold
 * start reliably raises an ANR a minute or two in — see Gotchas in SKILL.md.
 * The UI behind it is fine and the run can continue, but the dialog swallows
 * every tap until it is answered, and BACK does not answer it: only "Wait"
 * does.
 */
async function limparAnr() {
  let janelas = '';
  try {
    janelas = adb(['shell', 'dumpsys window'], { silencioso: true });
  } catch {
    return false;
  }
  if (!/not responding/i.test(janelas)) return false;
  const [x, y] = px(0.296, 0.555); // "Wait"
  shell(`input tap ${x} ${y}`);
  await dormir(1500);
  return true;
}


/** The raw framebuffer. `exec-out` and not `shell`: `shell` mangles the PNG. */
function capturar() {
  return adb(['exec-out', 'screencap', '-p'], { binario: true, silencioso: true });
}

/**
 * Waits until the screen stops changing.
 *
 * Two identical consecutive frames means the route transition has landed and
 * a tap will reach the widget that is actually there. Returns false on
 * timeout rather than throwing: an animation that never settles (a spinner,
 * a blinking cursor) is still a screen you can act on.
 */
async function assentar({ limiteMs = 8000, intervaloMs = 400, anr = true } = {}) {
  const ate = Date.now() + limiteMs;
  let anterior = null;
  let voltas = 0;
  while (Date.now() < ate) {
    // The ANR dialog can land at any moment, and once it does the screen is
    // perfectly stable — so a settle that ignored it would report success and
    // hand the next tap to a dialog. Checked here rather than only before a
    // tap, because "at any moment" includes the middle of a wait.
    if (anr && voltas % 3 === 0 && (await limparAnr())) {
      anterior = null;
      continue;
    }
    voltas++;
    const agora = createHash('sha1').update(capturar()).digest('hex');
    if (anterior === agora) return true;
    anterior = agora;
    await dormir(intervaloMs);
  }
  return false;
}

/**
 * Settles, then keeps watching in case the screen was only pretending.
 *
 * A splash screen is a still image, so `assentar` calls it settled and the
 * next tap lands on a logo. This waits out any further transition: settle,
 * watch for `janelaMs`, and if something moves, settle again. Bounded, so an
 * app that never stops animating still returns.
 */
async function assentarProfundo({ janelaMs = 6000, voltas = 4 } = {}) {
  for (let i = 0; i < voltas; i++) {
    await assentar({ limiteMs: 15000 });
    const estavel = createHash('sha1').update(capturar()).digest('hex');
    const ate = Date.now() + janelaMs;
    let mexeu = false;
    while (Date.now() < ate) {
      await dormir(700);
      if (createHash('sha1').update(capturar()).digest('hex') !== estavel) {
        mexeu = true;
        break;
      }
    }
    if (!mexeu) return;
  }
}

let geometria = null;
function ecra() {
  if (geometria) return geometria;
  const saida = shell('wm size');
  const m = /(\d+)x(\d+)/.exec(saida);
  geometria = m ? { w: +m[1], h: +m[2] } : { w: 1080, h: 2400 };
  return geometria;
}

/** Fractions in, device pixels out. */
function px(fx, fy) {
  const { w, h } = ecra();
  return [Math.round(fx * w), Math.round(fy * h)];
}

async function tocar(fx, fy) {
  await limparAnr();
  const [x, y] = px(fx, fy);
  shell(`input tap ${x} ${y}`);
  await assentar();
}

async function escrever(texto) {
  await limparAnr();
  // `input text` takes no spaces; %s is the documented stand-in.
  shell(`input text "${String(texto).replace(/"/g, '').replace(/ /g, '%s')}"`);
  await assentar();
}

async function tecla(codigo) {
  shell(`input keyevent ${codigo}`);
  await assentar();
}

function guardar(nome) {
  if (!existsSync(CAPTURAS)) mkdirSync(CAPTURAS, { recursive: true });
  const destino = join(CAPTURAS, `${nome || 'ecra'}.png`);
  writeFileSync(destino, capturar());
  return destino;
}

/* ----------------------------------------------------------- os alvos fixos */

/**
 * Fractions of the screen, read off a 1080x2400 Medium_Phone.
 *
 * The PIN pad and the numeric keypad are different widgets at different
 * places; the app's own pad is the one on the PIN screens.
 */
const ALVO = {
  areaDeNegocio: [0.851, 0.628],
  campoTelefone: [0.611, 0.528],
  // Measured with no keyboard up. An earlier value of 0.535 came from a
  // screenshot taken while the system keyboard was open, which lifts the
  // whole card — tapping there hits the SMS notice and sends nothing.
  continuarTelefone: [0.5, 0.708],
  pad: {
    1: [0.276, 0.602], 2: [0.5, 0.602], 3: [0.723, 0.602],
    4: [0.276, 0.702], 5: [0.5, 0.702], 6: [0.723, 0.702],
    7: [0.276, 0.803], 8: [0.5, 0.803], 9: [0.723, 0.803],
    0: [0.5, 0.903], del: [0.723, 0.903],
  },
};

/* --------------------------------------------------------------- os comandos */

async function arrancar() {
  const ligados = execFileSync(ADB, ['devices'], { encoding: 'utf8' });
  if (!ligados.includes(SERIE)) {
    console.log(`a arrancar o AVD ${AVD}…`);
    execFileSync('flutter', ['emulators', '--launch', AVD], {
      encoding: 'utf8',
      stdio: 'inherit',
      shell: true,
    });
  }
  process.stdout.write('a esperar pelo arranque');
  for (let i = 0; i < 60; i++) {
    try {
      const pronto = adb(['shell', 'getprop sys.boot_completed'], { silencioso: true }).trim();
      if (pronto === '1') {
        console.log('\narrancado.');
        return;
      }
    } catch {
      /* ainda offline */
    }
    process.stdout.write('.');
    await dormir(5000);
  }
  throw new Error('o emulador não arrancou a tempo');
}

/**
 * Builds and installs, wired to the Firebase emulators.
 *
 * `flutter build` and then `adb install`, deliberately not `flutter run`.
 * `flutter run` holds the terminal and, backgrounded, exits and takes the
 * app down with it — which is exactly the trap that makes the app appear to
 * die on its own. Building the APK once and installing it means every later
 * `launch` is a plain `am start` that needs no flutter at all.
 *
 * The dart-defines are compile-time, so they are baked in here and the
 * installed APK stays wired to the emulators until it is rebuilt.
 */
function instalar({ emuladores = true } = {}) {
  const defines = emuladores
    ? [
        '--dart-define=USE_FIREBASE_EMULATORS=true',
        // An Android emulator reaches the host's loopback at 10.0.2.2, never
        // at 127.0.0.1 — the default sends it looking inside the guest.
        '--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2',
      ]
    : [];

  console.log('flutter build apk --debug ' + defines.join(' '));
  execFileSync('flutter', ['build', 'apk', '--debug', ...defines], {
    stdio: 'inherit',
    shell: true,
    cwd: RAIZ,
    timeout: 20 * 60 * 1000,
  });

  const apk = join(RAIZ, 'build', 'app', 'outputs', 'flutter-apk', 'app-debug.apk');
  if (!existsSync(apk)) throw new Error(`o build não deixou APK em ${apk}`);
  console.log(`adb install -r ${apk}`);
  adb(['install', '-r', apk]);
}

async function lancar() {
  // `monkey` echoes the args it parsed to stderr; noise, not failure. It is
  // used rather than `am start -n …/.MainActivity` because that spelling of
  // the activity is wrong for this app and fails with "does not exist".
  adb(['shell', `monkey -p ${PACOTE} -c android.intent.category.LAUNCHER 1`], {
    silencioso: true,
  });
  await dormir(3000);
  // The `workmanager` plugin schedules a job whose `onStartJob` never
  // answers, and Android raises "MaisUm isn't responding" about a minute in —
  // every time, on a cold start. The dialog then eats every tap. Cancelling
  // the app's jobs removes the cause instead of swatting the symptom; nothing
  // in the foreground flow depends on them.
  try {
    adb(['shell', `cmd jobscheduler cancel ${PACOTE}`], { silencioso: true });
  } catch {
    /* sem jobs agendados, tanto melhor */
  }
  await limparAnr();
  await assentarProfundo();
}

async function reiniciar() {
  shell(`am force-stop ${PACOTE}`);
  await dormir(1500);
  await lancar();
}

/** Wipes local state: PIN, session, the whole SQLite database. */
async function limpar() {
  shell(`pm clear ${PACOTE}`);
  await dormir(1500);
  await lancar();
}

/**
 * The SMS code, from the auth emulator rather than from an SMS.
 *
 * The emulator never sends anything; it records what it would have sent.
 * Without this endpoint the sign-in flow cannot be automated at all.
 */
async function codigos(telefone) {
  const url = `http://127.0.0.1:9099/emulator/v1/projects/${PROJETO}/verificationCodes`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`o emulador de auth respondeu ${res.status}`);
  const { verificationCodes = [] } = await res.json();
  return telefone
    ? verificationCodes.filter((v) => v.phoneNumber === telefone)
    : verificationCodes;
}

async function otp(telefone) {
  const lista = await codigos(telefone);
  const ultimo = lista[lista.length - 1];
  if (!ultimo) throw new Error('nenhum código pedido ainda');
  return ultimo.code;
}

/**
 * Waits for a code that did not exist before the request was made.
 *
 * The emulator keeps every code it ever issued, so simply taking the last
 * one hands back a stale code from an earlier run — which the app rejects,
 * silently, leaving the flow parked on a screen that looks fine. Passing
 * the count from before the request is what makes "new" mean new.
 */
async function otpNovo(telefone, jaHavia, limiteMs = 60000) {
  const ate = Date.now() + limiteMs;
  while (Date.now() < ate) {
    const lista = await codigos(telefone);
    if (lista.length > jaHavia) return lista[lista.length - 1].code;
    await dormir(700);
  }
  throw new Error(
    `nenhum código novo para ${telefone} em ${limiteMs / 1000}s — ` +
      'o pedido chegou a ser enviado? veja shots/',
  );
}

function estado() {
  // `pidof` exits 1 when the app is not running, which is an answer, not a
  // failure — the whole point of asking.
  let pid = '';
  try {
    pid = shell(`pidof ${PACOTE}`).trim();
  } catch {
    pid = '';
  }
  const topo = shell('dumpsys activity activities')
    .split('\n')
    .find((l) => l.includes('topResumedActivity')) || '';
  const erros = shell('logcat -d -t 400')
    .split('\n')
    .filter((l) => /FATAL|AndroidRuntime: .*Exception|E flutter/.test(l))
    .slice(-5);
  return {
    aCorrer: pid !== '',
    pid: pid || null,
    emPrimeiroPlano: topo.includes(PACOTE),
    emuladoresFirebase: shell('logcat -d')
      .split('\n')
      .filter((l) => l.includes('Firebase emulators:'))
      .slice(-1)[0]?.trim() || null,
    erros,
  };
}

function registos(padrao = 'flutter') {
  return shell('logcat -d -t 600')
    .split('\n')
    .filter((l) => new RegExp(padrao, 'i').test(l))
    .filter((l) => !/FlutterJNI|ResourceExtractor|Impeller|ProfileInstaller|WM-|ImeTracker/.test(l))
    .slice(-40)
    .join('\n');
}

/**
 * Role gate -> phone -> OTP -> PIN, in one go.
 *
 * Every step waits for the screen to settle, which is what makes it
 * repeatable; doing this by hand on fixed sleeps loses roughly one tap in
 * four. The phone defaults to the business seeded by the portal's
 * `admin/scripts/seed-dev.mjs`, so the app lands on that business and its
 * data rather than on an empty one.
 */
async function entrar({ telefone = '840000001', pin = '1234', doZero = true } = {}) {
  const digitos = (s) => [...String(s)];

  // Owns its starting state. Run twice in a row without this and the second
  // run begins wherever the first one stopped — which, the first time this
  // happened, was the *customer* phone screen, where the business taps land
  // on nothing and the failure reads as "the role gate did not respond".
  if (doZero) {
    console.log('· estado limpo');
    await limpar();
  }

  console.log('· portão de perfis');
  await tocar(...ALVO.areaDeNegocio);

  console.log('· número de telefone');
  await tocar(...ALVO.campoTelefone);
  await escrever(telefone);

  // Deliberately no ESC/BACK to dismiss the keyboard: in Flutter both pop the
  // route, which sends the flow back to an empty phone field and leaves the
  // rest of the run typing into nothing. CONTINUAR is reachable with the
  // keyboard up, so it is simply tapped where it sits.
  const jaHavia = (await codigos(`+258${telefone}`)).length;
  await tocar(...ALVO.continuarTelefone);

  console.log('· código de verificação');
  const codigo = await otpNovo(`+258${telefone}`, jaHavia);
  console.log(`  código = ${codigo}`);
  await escrever(codigo);
  await assentar({ limiteMs: 15000 });

  console.log('· criar PIN');
  for (const d of digitos(pin)) await tocar(...ALVO.pad[d]);
  // The create -> confirm transition swallows anything sent during it.
  await assentar({ limiteMs: 12000 });
  await dormir(1500);

  console.log('· confirmar PIN');
  for (const d of digitos(pin)) await tocar(...ALVO.pad[d]);
  await assentar({ limiteMs: 20000 });

  const destino = guardar('depois-de-entrar');
  console.log(`captura: ${destino}`);
  console.log('(confirme na captura onde ficou: onboarding ou painel)');
}

/* --------------------------------------------------------------------- main */

const AJUDA = `
uso: node .claude/skills/run-maisum/driver.mjs <comando> [args]

  boot                arranca o AVD e espera pelo arranque
  install             flutter build apk + adb install, com os dart-defines
  launch              abre o APK já instalado (não precisa do flutter)
  relaunch            force-stop + abre
  reset               pm clear (apaga PIN, sessão e base local) + abre
  signin [tel] [pin]  portão -> telefone -> OTP -> PIN, tudo seguido
  ss [nome]           captura para shots/<nome>.png
  tap <fx> <fy>       toque em fracções do ecrã (0..1), espera assentar
  text <texto>        escreve no campo com foco
  key <codigo>        keyevent (4=voltar, 111=esc, 67=backspace)
  otp [+258…]         código SMS do emulador de auth
  state               a correr? em primeiro plano? erros? emuladores?
  logs [padrão]       linhas recentes do logcat

variáveis: ADB, ANDROID_SERIAL (por omissão emulator-5554)
`;

const [, , comando, ...args] = process.argv;

try {
  switch (comando) {
    case 'boot': await arrancar(); break;
    case 'install': instalar(); break;
    case 'launch': await lancar(); console.log(guardar('launch')); break;
    case 'relaunch': await reiniciar(); console.log(guardar('relaunch')); break;
    case 'reset': await limpar(); console.log(guardar('reset')); break;
    case 'signin': await entrar({ telefone: args[0], pin: args[1] }); break;
    case 'ss': console.log(guardar(args[0])); break;
    case 'tap': await tocar(parseFloat(args[0]), parseFloat(args[1])); console.log(guardar('tap')); break;
    case 'text': await escrever(args.join(' ')); break;
    case 'key': await tecla(args[0]); break;
    case 'otp': console.log(await otp(args[0])); break;
    case 'state': console.log(JSON.stringify(estado(), null, 2)); break;
    case 'logs': console.log(registos(args[0])); break;
    default: console.log(AJUDA); process.exit(comando ? 1 : 0);
  }
} catch (erro) {
  console.error(`\nfalhou: ${erro.message}`);
  process.exit(1);
}
