plugins {
    kotlin("jvm")
    kotlin("plugin.serialization")
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.0")
    testImplementation(kotlin("test"))
}

tasks.test {
    val fixtureRoot = rootProject.projectDir.resolve("../../Fixtures").canonicalFile
    useJUnitPlatform()
    inputs.dir(fixtureRoot)
    systemProperty("mtog.fixtureRoot", fixtureRoot.path)
}
