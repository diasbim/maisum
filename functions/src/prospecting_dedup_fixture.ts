/**
 * The Maputo run, as the API returned it.
 *
 * A real search — "barbershop em Maputo", twenty results, $0.17 spent, of
 * which $0.06 bought the same phone number three times. Kept as its own
 * module because two things need it: the deduplication tests, and the harness
 * `--fixture` mode that replays the run without calling Google.
 *
 * Names, ratings and review counts are as they came back, including the three
 * apostrophes. Those are the point and must not be tidied up. The coordinates
 * are reconstructed — the original run predates asking for them — and only
 * their proximity matters: the three Gentleman listings stand metres apart,
 * every other business is streets away.
 */

const ACUTE = String.fromCharCode(0x00b4);
const CURLY = String.fromCharCode(0x2019);
const PLAIN = String.fromCharCode(0x27);

/** The same street corner, to within a few metres. */
const GENTLEMANS = { latitude: -25.9655, longitude: 32.5832 };

export type MaputoRow = {
  sourceReference: string | null;
  name: string;
  rating: number | null;
  reviewCount: number | null;
  latitude: number | null;
  longitude: number | null;
};

const at = (
  point: { latitude: number; longitude: number },
  metresEast: number,
): { latitude: number; longitude: number } => ({
  latitude: point.latitude,
  // Rough, and rough is fine: the tests assert either "well inside 150 m" or
  // "well outside", never a boundary that a better conversion would move.
  longitude: point.longitude + metresEast / (111_320 * Math.cos((point.latitude * Math.PI) / 180)),
});

export const MAPUTO_RUN: readonly MaputoRow[] = [
  {
    sourceReference: 'p-gentleman-acute',
    name: 'Gentleman' + ACUTE + 's Barber Shop',
    rating: 4.5,
    reviewCount: 56,
    ...GENTLEMANS,
  },
  {
    sourceReference: 'p-gentleman-curly',
    name: 'Gentleman' + CURLY + 's Barber Shop',
    rating: 4.5,
    reviewCount: 41,
    ...at(GENTLEMANS, 12),
  },
  {
    sourceReference: 'p-gentleman-plain',
    name: 'Gentleman' + PLAIN + 's Barber Shop',
    rating: 4.5,
    reviewCount: 56,
    ...at(GENTLEMANS, 5),
  },
  {
    sourceReference: 'p-tsemeta',
    name: 'Tsemeta Barbershop',
    rating: 4.6,
    reviewCount: 61,
    latitude: -25.9701,
    longitude: 32.5744,
  },
  {
    sourceReference: 'p-tchetcho',
    name: "Tchetcho's Barber Shop",
    rating: 4.4,
    reviewCount: 107,
    latitude: -25.9548,
    longitude: 32.589,
  },
  {
    sourceReference: 'p-kubila',
    name: 'KUBILA BARBER SHOP',
    rating: 4.5,
    reviewCount: 39,
    latitude: -25.9612,
    longitude: 32.5801,
  },
  {
    sourceReference: 'p-hair-studio',
    name: 'Hair Studio',
    rating: 4.8,
    reviewCount: 35,
    latitude: -25.9489,
    longitude: 32.5955,
  },
  {
    sourceReference: 'p-mancave',
    name: 'ManCave',
    rating: 4.7,
    reviewCount: 43,
    latitude: -25.9523,
    longitude: 32.5908,
  },
  {
    sourceReference: 'p-na-regua',
    name: 'Na Régua Barbershop',
    rating: 4.7,
    reviewCount: 29,
    latitude: -25.9668,
    longitude: 32.5779,
  },
  {
    sourceReference: 'p-level-up',
    name: 'Level Up Barber MZ',
    rating: 5,
    reviewCount: 2,
    latitude: -25.9571,
    longitude: 32.5866,
  },
  {
    sourceReference: 'p-dos-anjos',
    name: 'Barber Shop Dos Anjos',
    rating: 5,
    reviewCount: 1,
    latitude: -25.9634,
    longitude: 32.5823,
  },
  {
    sourceReference: 'p-fogueira',
    name: 'Fogueira-Barbershop',
    rating: 4.6,
    reviewCount: 9,
    latitude: -25.9599,
    longitude: 32.5771,
  },
  {
    sourceReference: 'p-cb-barbear',
    name: 'CB Barbear Studio',
    rating: 5,
    reviewCount: 3,
    latitude: -25.9505,
    longitude: 32.5931,
  },
  {
    sourceReference: 'p-fio',
    name: 'FIObarbershop',
    rating: 5,
    reviewCount: 1,
    latitude: -25.9683,
    longitude: 32.5758,
  },
  {
    sourceReference: 'p-patricio',
    name: 'Barbearia shopping Patrício Este',
    rating: 5,
    reviewCount: 1,
    latitude: -25.9462,
    longitude: 32.5977,
  },
  {
    sourceReference: 'p-mabotizy',
    name: 'Mabotizy Barbershop',
    rating: 5,
    reviewCount: 5,
    latitude: -25.9717,
    longitude: 32.5726,
  },
  {
    sourceReference: 'p-tongas',
    name: 'Tongas studio',
    rating: null,
    reviewCount: null,
    latitude: -25.9556,
    longitude: 32.5847,
  },
  {
    sourceReference: 'p-rei-do-estilo',
    name: 'REI DO ESTILO',
    rating: null,
    reviewCount: null,
    latitude: -25.9644,
    longitude: 32.5812,
  },
  {
    sourceReference: 'p-celdz',
    name: 'Celdz',
    rating: null,
    reviewCount: null,
    latitude: -25.9588,
    longitude: 32.5889,
  },
  {
    sourceReference: 'p-golden-cut',
    name: 'Golden cut',
    rating: null,
    reviewCount: null,
    latitude: -25.9531,
    longitude: 32.5942,
  },
];

