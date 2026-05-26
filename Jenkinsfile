pipeline {
    agent any

    parameters {
        string(name: 'SDK_VERSION', defaultValue: '13.0.0_rc1')
        string(name: 'ARCH', defaultValue: 'aarch64')
    }

    stages {

        stage('Download SDK') {
            steps {
                sh '''
                mkdir -p sdk
                cd sdk

                echo "Simulating download..."
                # Replace with real wget later
                touch ACAPSDK_${SDK_VERSION}_${ARCH}_setup.sh
                '''
            }
        }

        stage('Extract SDK') {
            steps {
                sh '''
                cd sdk

                echo "Simulating extraction..."
                mkdir -p sdk-extracted/bin
                echo "fake-toolchain" > sdk-extracted/bin/compiler
                '''
            }
        }

        stage('Build Docker') {
            steps {
                sh '''
                docker build -t my-acap-sdk:${ARCH} .
                '''
            }
        }
    }
}
