allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Ensure all Android library/application subprojects compile against the desired SDK
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                val setCompileSdk = androidExt.javaClass.methods.firstOrNull { it.name == "setCompileSdk" || it.name == "setCompileSdkVersion" }
                if (setCompileSdk != null) {
                    setCompileSdk.invoke(androidExt, 36)
                } else {
                    // fallback to property if available
                    try {
                        val prop = androidExt.javaClass.getDeclaredField("compileSdk")
                        prop.isAccessible = true
                        prop.set(androidExt, 36)
                    } catch (_: Exception) { }
                }
            } catch (_: Exception) { }
        }
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
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
