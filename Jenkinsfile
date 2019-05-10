@Library('tiger-ci') _

def registry = 'https://docker.cloudbees.com'
def registryCredentials = 'docker.cloudbees.com'

def releaseRegistry = ''
def releaseRegistryCredentials = 'dockerhub'

def imageName = 'docker-certificates'

def withDir(String name, body) {
    dir(name) {
        try {
            body()
        } finally {
            deleteDir()
        }
    }
}

def loginToDockerRegistry(String registry, String registryCredentials) {
    withCredentials([[$class          : 'UsernamePasswordMultiBinding',
                      credentialsId   : registryCredentials,
                      passwordVariable: 'DOCKER_PASSWORD',
                      usernameVariable: 'DOCKER_USER']]) {
        sh "docker login -u \"\$DOCKER_USER\" -p \"\$DOCKER_PASSWORD\" \"$registry\""
    }
}

def dockerTag(def img, String dest) {
    sh "docker tag ${dest} ${img.id}"
    return docker.image(dest)
}

def tag = "cloudbees/$imageName:${env.BUILD_NUMBER}"
currentBuild.displayName = "#${currentBuild.number} (${tag})"
def dockerImg = docker.image(tag)

timestamps {
    node('pse-ci') {
        withDir('work') {
            stage('Checkout') {
                checkout scm
            }
            stage('Build') {
                wrap([$class: 'AnsiColorBuildWrapper', colorMapName: 'xterm']) {
                    loginToDockerRegistry(registry, registryCredentials)
                    withMaven(
                            mavenSettingsConfig: 'maven-settings-nexus-internal-ci-release-jobs',
                            mavenSettingsFilePath: 'settings.xml') {
                        sh "mvn -B -U clean install -Ddocker.imagePullPolicy=always -DdockerImage=${tag}"
                    }
                }
            }

            stage('Test') {
                sh "./test.sh"
            }
            stage('Deploy') {
                docker.withRegistry(registry, registryCredentials) {
                    dockerImg.push()
                }
            }
        }
    }
    def releaseVersion = null

    stage('Prompt for release') {
        checkpoint 'Before prompting for release'
        try {
            timeout(time: 2, unit: 'HOURS') {
                releaseVersion = input(
                        message: 'Do you want to release the docker image ?',
                        parameters: [
                                string(
                                        name: 'version',
                                        description: 'Tag that will be used to release the image'
                                )
                        ]
                )
            }
        } catch (err) {
            // Timeout or abort should succeed the build
            currentBuild.result = 'SUCCESS'
        }
    }
    if (releaseVersion) {
        node('pse-ci') {
            stage('Tag') {
                checkout scm
                sshagent(['github-ssh']) {
                    sh """
                    git tag -f $releaseVersion
                    git push -f origin $releaseVersion
                """
                }

            }
            stage('Release') {
                def releaseTag = "cloudbees/$imageName:${releaseVersion}"
                currentBuild.displayName = "#${currentBuild.number} RELEASE (${releaseTag})"
                def releaseImg
                docker.withRegistry(registry, registryCredentials) {
                    dockerImg.pull()
                    releaseImg = dockerTag(dockerImg, releaseTag)
                }
                docker.withRegistry(releaseRegistry, releaseRegistryCredentials) {
                    releaseImg.push()
                }
            }
        }
        // Update Tiger
        stage('Update Tiger') {
            updateTiger app: 'docker-certificates', version: releaseVersion
        }
    }
}