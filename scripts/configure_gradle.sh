#!/usr/bin/env bash
set -euo pipefail
task_script_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$task_script_root/cloud_env.sh"
mkdir -p "$GRADLE_USER_HOME/init.d"

# The shared cloud egress address is rate-limited by Maven Central. Google's
# public Maven Central mirror serves the same artifacts over verified HTTPS.
# Scope this override to the cloud cache; leave project repositories intact.
cat > "$GRADLE_USER_HOME/init.d/erp-central-mirror.gradle" <<'GROOVY'
import org.gradle.api.initialization.resolve.RepositoriesMode

def useSettingsRepositories = false
def addCentralMirror = { repositories ->
    def mirror = repositories.findByName('ErpCloudCentralMirror')
    if (mirror == null) {
        mirror = repositories.maven {
            name = 'ErpCloudCentralMirror'
            url = uri('https://storage.googleapis.com/maven-central/maven2')
        }
    }
    repositories.remove(mirror)
    repositories.addFirst(mirror)
}
gradle.beforeSettings { settings ->
    // Android plugin markers live in Google's official repository. Resolve
    // them before the plugin portal can redirect a miss to rate-limited Central.
    settings.pluginManagement.repositories.google()
    // Adding a repository suppresses Gradle's implicit plugin portal, so
    // retain that official source for plugin markers absent from Central.
    settings.pluginManagement.repositories.gradlePluginPortal()
    addCentralMirror(settings.pluginManagement.repositories)
}
gradle.settingsEvaluated { settings ->
    addCentralMirror(settings.pluginManagement.repositories)
    addCentralMirror(settings.dependencyResolutionManagement.repositories)
    useSettingsRepositories = settings.dependencyResolutionManagement.repositoriesMode.get() != RepositoriesMode.PREFER_PROJECT
}
gradle.beforeProject { project ->
    addCentralMirror(project.buildscript.repositories)
    if (!useSettingsRepositories) {
        addCentralMirror(project.repositories)
    }
}
GROOVY
