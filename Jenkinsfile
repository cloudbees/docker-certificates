node ('docker') {
    stage('Checkout') {
        checkout scm
    }
    stage('Build') {
        sh "docker build -t docker-certificates:build-${env.BUILD_NUMBER} ."
    }
    stage('Test') {
        sh "./test.sh"
    }
}
