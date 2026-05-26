buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    afterEvaluate {
        if (name == "telephony") {
            val androidExtension = extensions.findByName("android")
            val setNamespace = androidExtension
                ?.javaClass
                ?.methods
                ?.firstOrNull { method ->
                    method.name == "setNamespace" && method.parameterTypes.contentEquals(arrayOf(String::class.java))
                }
            if (setNamespace != null) {
                setNamespace.invoke(androidExtension, "com.shounakmulay.telephony")
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
