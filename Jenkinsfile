pipeline {
    agent any

    environment {
        APP_VERSION = "${env.BUILD_NUMBER}"
        // Hardcode the IP of your manually-launched EC2 for now
        // Later, when Terraform works, this will come from `terraform output`
        SERVER_IP = '3.248.231.68'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Test') {
            steps {
                sh '''
                    cd app
                    python3 -m venv venv
                    . venv/bin/activate
                    pip install -r requirements.txt
                    pytest -v
                '''
            }
        }

      //   stage('Build Docker image') {
      //       steps {
      //           sh 'docker build -t flask-app:${BUILD_NUMBER} ./app'
      //       }
      //   }

        stage('Configure & deploy') {
            steps {
                sh '''
                    cd ansible
                    echo "[webservers]" > dynamic_inventory.ini
                    echo "app_server ansible_host=${SERVER_IP} ansible_user=ubuntu ansible_ssh_private_key_file=/var/jenkins_home/.ssh/devops-tutorial.pem" >> dynamic_inventory.ini
                    echo "" >> dynamic_inventory.ini
                    echo "[webservers:vars]" >> dynamic_inventory.ini
                    echo "ansible_python_interpreter=/usr/bin/python3" >> dynamic_inventory.ini
                    echo "ansible_host_key_checking=False" >> dynamic_inventory.ini

                    ansible-playbook -i dynamic_inventory.ini playbook.yml
                '''
            }
        }

        stage('Smoke test') {
            steps {
                sh '''
                    sleep 15
                    curl -f http://${SERVER_IP}/health
                '''
            }
        }
    }

    post {
        success {
            echo "Deployed version ${APP_VERSION} successfully to ${SERVER_IP}"
        }
        failure {
            echo "Pipeline failed — check the logs"
        }
    }
}