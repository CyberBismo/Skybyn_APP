import java.util.Properties
import java.io.FileInputStream
import com.android.build.gradle.BaseExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    
    // Ensure app is evaluated first if it's not this project
    if (project.path != ":app") {
        project.evaluationDependsOn(":app")
    } else {
        // Skip the rest of the logic for the :app module itself
        return@subprojects
    }

    val configureAndroid: Project.() -> Unit = {
        if (extensions.findByName("android") != null) {
            extensions.configure<BaseExtension> {
                println(">>> Project ${project.name}: Changing compileSdkVersion from $compileSdkVersion to 36")
                compileSdkVersion(36)
            }
        }
    }

    if (state.executed) {
        configureAndroid()
    } else {
        afterEvaluate { configureAndroid() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
