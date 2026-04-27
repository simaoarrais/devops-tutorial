# CI/CD & DevOps Tutorial — End-to-End Project

**Stack:** GitHub Actions · Jenkins · Terraform · Ansible
**Cloud:** AWS · **App:** Python (Flask)
**Audience:** Beginners preparing for DevOps/SRE job interviews

---

## How to Use This Tutorial

Work through the sections in order. Each section has three parts:

1. **Concept** — what the tool is and *why it exists* (this is what interviewers probe)
2. **Hands-on** — minimal working example you'll actually run
3. **Interview angles** — the questions you'll get asked and how to frame answers

By the end you'll have a real pipeline that: provisions an AWS EC2 server with Terraform, configures it with Ansible, runs tests on every commit via GitHub Actions, and orchestrates deployments with Jenkins.

---

## Table of Contents

1. [Big Picture — How These Tools Fit Together](#1-big-picture)
2. [Prerequisites & Setup](#2-prerequisites--setup)
3. [The Demo App](#3-the-demo-app)
4. [Terraform — Infrastructure as Code](#4-terraform)
5. [Ansible — Configuration Management](#5-ansible)
6. [GitHub Actions — Continuous Integration](#6-github-actions)
7. [Jenkins — The Orchestrator](#7-jenkins)
8. [Putting It All Together](#8-putting-it-all-together)
9. [Interview Prep Cheat Sheet](#9-interview-prep-cheat-sheet)

---

<a name="1-big-picture"></a>
## 1. Big Picture — How These Tools Fit Together

### The core DevOps problem

Before automation, releasing software looked like this: developer writes code → emails a zip file to operations → ops logs into a server → manually installs dependencies → manually copies files → manually restarts services → something breaks at 2am → nobody remembers what was changed.

DevOps tools exist to make every step of that flow **automated, repeatable, and version-controlled**.

### The four tools, by the job they do

| Layer | Tool | Question it answers |
|-------|------|---------------------|
| **Infrastructure** | Terraform | *What servers/networks/databases should exist?* |
| **Configuration** | Ansible | *How should each server be set up?* |
| **Continuous Integration** | GitHub Actions | *Does this code build and pass tests?* |
| **Continuous Delivery** | Jenkins | *Orchestrate the full pipeline: build → test → provision → deploy* |

### The pipeline visually

```
Developer pushes code to GitHub
         │
         ▼
┌─────────────────────────┐
│  GitHub Actions         │  ← fast feedback: lint, unit tests
│  (runs on every push)   │
└────────────┬────────────┘
             │ (tests pass)
             ▼
┌─────────────────────────┐
│  Jenkins                │  ← orchestrates deployment
│  - Build Docker image   │
│  - Run Terraform        │  ──► AWS: EC2, VPC, Security Groups
│  - Run Ansible          │  ──► Install Python, nginx, deploy app
│  - Smoke test           │
└─────────────────────────┘
```

### Why both GitHub Actions AND Jenkins?

Honest answer: most companies pick **one**. They overlap significantly. But learning both is valuable because:

- **GitHub Actions** wins for cloud-native/SaaS shops. Zero infrastructure, pay-per-use, tightly integrated with GitHub.
- **Jenkins** wins for enterprises that need self-hosted control, have complex pipelines, or exist in regulated environments (banks, healthcare, defense).

In this tutorial, GitHub Actions handles **fast CI checks** (lint, unit tests — 30 seconds) and Jenkins handles **heavier deployment orchestration**. This split is a real pattern you'll see in the wild.

### Declarative vs. Imperative — the big mental model

Terraform and Ansible are **declarative**: you describe the *desired state* and the tool figures out how to get there. If you run them twice, the second run does nothing (this property is called **idempotency**).

Jenkins pipelines and shell scripts tend to be **imperative**: you write the *steps*. Running twice would do it twice.

> **Interview answer prep:** "Idempotency means running the same operation multiple times produces the same result. Terraform and Ansible are idempotent — you can re-run them safely. This matters because infrastructure changes are scary, and idempotency lets you re-run with confidence."

---

<a name="2-prerequisites--setup"></a>
## 2. Prerequisites & Setup

### What you need installed locally

```bash
# Check what you have
git --version
python3 --version
docker --version
terraform --version
ansible --version
aws --version
```

Install what's missing:

- **Git** — [git-scm.com](https://git-scm.com)
- **Python 3.10+** — [python.org](https://python.org)
- **Docker Desktop** — needed for local Jenkins
- **Terraform** — `brew install terraform` (mac) or see [hashicorp docs](https://developer.hashicorp.com/terraform/install)
- **Ansible** — `pip install ansible` or `brew install ansible`
- **AWS CLI** — `brew install awscli` or see [AWS docs](https://docs.aws.amazon.com/cli/)

### AWS account setup

1. Create a free-tier AWS account.
2. Create an **IAM user** named `devops-tutorial` with programmatic access.
3. Attach policy `AmazonEC2FullAccess` (for learning — production would be tighter).
4. Save the access key and secret.
5. Configure locally:

```bash
aws configure
# AWS Access Key ID: AKIA...
# AWS Secret Access Key: ...
# Default region: eu-west-1      # or your preferred region
# Default output format: json
```

6. Create an **SSH key pair** in AWS Console → EC2 → Key Pairs. Name it `devops-tutorial`. Download the `.pem` file and save it to `~/.ssh/devops-tutorial.pem`. Set permissions:

```bash
chmod 400 ~/.ssh/devops-tutorial.pem
```

### Project structure

Create a folder and set this structure:

```
devops-tutorial/
├── app/                    # The Python app
│   ├── app.py
│   ├── requirements.txt
│   └── test_app.py
├── terraform/              # Infrastructure code
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── ansible/                # Config management
│   ├── inventory.ini
│   ├── playbook.yml
│   └── templates/
│       └── nginx.conf.j2
├── .github/workflows/      # GitHub Actions
│   └── ci.yml
├── Jenkinsfile             # Jenkins pipeline
└── README.md
```

```bash
mkdir -p devops-tutorial/{app,terraform,ansible/templates,.github/workflows}
cd devops-tutorial
git init
```

---

<a name="3-the-demo-app"></a>
## 3. The Demo App

A tiny Flask app — small enough to not distract, real enough to deploy.

**`app/app.py`**

```python
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route("/")
def home():
    return jsonify({
        "message": "Hello from the DevOps tutorial!",
        "version": os.environ.get("APP_VERSION", "dev"),
    })

@app.route("/health")
def health():
    return jsonify({"status": "ok"}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
```

**`app/requirements.txt`**

```
flask==3.0.0
pytest==8.0.0
```

**`app/test_app.py`**

```python
from app import app

def test_home():
    client = app.test_client()
    response = client.get("/")
    assert response.status_code == 200
    assert b"Hello" in response.data

def test_health():
    client = app.test_client()
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json()["status"] == "ok"
```

Run it locally to verify:

```bash
cd app
pip install -r requirements.txt
pytest              # tests pass
python app.py       # app runs on :8000
```

---

<a name="4-terraform"></a>
## 4. Terraform — Infrastructure as Code

### Concept

Terraform lets you write your infrastructure (VMs, networks, databases, DNS records) as **code files** that you commit to git. You run `terraform apply` and Terraform talks to AWS's API to make reality match your files.

**Why this matters:** Before Terraform, people clicked through AWS Console to set things up. Nobody could recreate environments. Staging drifted from production. Disasters took days to recover from. With Terraform, your entire environment is a `git clone` and `terraform apply` away.

**Key vocabulary:**
- **Provider** — plugin that talks to a specific cloud (aws, azurerm, google, etc.)
- **Resource** — a thing Terraform manages (an EC2 instance, a security group...)
- **State** — Terraform's memory of what it created. Stored in `terraform.tfstate`. In teams, this lives in S3 + DynamoDB for locking.
- **Plan** — preview of changes before applying.
- **Apply** — actually makes the changes.

### Hands-on

**`terraform/variables.tf`** — inputs to your config

```hcl
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "key_name" {
  description = "Name of the SSH key pair in AWS"
  type        = string
  default     = "devops-tutorial"
}

variable "instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t3.micro"   # free tier eligible
}
```

**`terraform/main.tf`** — the actual infrastructure

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Look up the latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Security group: allow SSH (22), HTTP (80), and our app port (8000) from anywhere
resource "aws_security_group" "app_sg" {
  name        = "devops-tutorial-sg"
  description = "Allow web and SSH traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # in production, restrict to your IP
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "devops-tutorial-sg" }
}

# The EC2 instance itself
resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  tags = {
    Name        = "devops-tutorial-app"
    Environment = "tutorial"
    ManagedBy   = "terraform"
  }
}
```

**`terraform/outputs.tf`** — surface info we need later

```hcl
output "public_ip" {
  description = "Public IP of the app server"
  value       = aws_instance.app_server.public_ip
}

output "ssh_command" {
  description = "Command to SSH into the instance"
  value       = "ssh -i ~/.ssh/devops-tutorial.pem ubuntu@${aws_instance.app_server.public_ip}"
}
```

### Run it

```bash
cd terraform
terraform init         # downloads the aws provider plugin
terraform plan         # shows what will be created — READ THIS CAREFULLY
terraform apply        # type 'yes' to confirm
```

After ~60 seconds you'll see:

```
Outputs:
public_ip = "54.123.45.67"
ssh_command = "ssh -i ~/.ssh/devops-tutorial.pem ubuntu@54.123.45.67"
```

Test SSH:

```bash
ssh -i ~/.ssh/devops-tutorial.pem ubuntu@<public_ip>
# you should land in the Ubuntu shell
exit
```

### When you're done experimenting

```bash
terraform destroy      # tears everything down so you don't get billed
```

### Interview angles

- **"What's the difference between Terraform and CloudFormation?"** Terraform is cloud-agnostic (one tool for AWS/Azure/GCP) and has better third-party module support. CloudFormation is AWS-only but has deeper AWS integration.
- **"What is the Terraform state file and why does it matter?"** It's Terraform's record of what it manages. If you lose it, Terraform doesn't know what exists. In teams, store it in S3 with DynamoDB for locking so two engineers can't apply simultaneously.
- **"What's `terraform plan` vs `apply`?"** Plan is a dry run showing proposed changes. Apply executes them. Always review the plan — it's your last line of defense before something gets destroyed.
- **"What is a Terraform module?"** A reusable bundle of resources. You can write a "web-server" module once and use it for dev/staging/prod.

---

<a name="5-ansible"></a>
## 5. Ansible — Configuration Management

### Concept

Terraform gave you an empty Ubuntu server. Ansible turns it into a running application server (installs Python, copies your app, sets up nginx, starts services).

**Why a separate tool?** You *could* do this with a bash script in Terraform's `user_data`. But:
- Ansible is **idempotent** — safe to re-run. Bash scripts aren't.
- Ansible is **agentless** — it just needs SSH. No software to install on target servers.
- Ansible is **declarative-ish** — you describe desired state ("nginx is installed and running"), not steps.

**Key vocabulary:**
- **Inventory** — list of servers to manage
- **Playbook** — YAML file describing what to do
- **Task** — a single action ("install package X")
- **Module** — built-in action types (`apt`, `copy`, `service`, `template`...)
- **Role** — reusable collection of tasks, like a Terraform module but for Ansible

### Hands-on

**`ansible/inventory.ini`** — tell Ansible about your server

```ini
[webservers]
app_server ansible_host=54.123.45.67 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/devops-tutorial.pem

[webservers:vars]
ansible_python_interpreter=/usr/bin/python3
```

Replace `54.123.45.67` with the `public_ip` Terraform output.

**`ansible/templates/nginx.conf.j2`** — nginx config (Jinja2 template)

```nginx
server {
    listen 80 default_server;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

**`ansible/playbook.yml`** — the main event

```yaml
---
- name: Configure web server and deploy Flask app
  hosts: webservers
  become: true   # use sudo
  vars:
    app_dir: /opt/flask-app
    app_user: flaskapp

  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes
        cache_valid_time: 3600

    - name: Install system packages
      apt:
        name:
          - python3
          - python3-pip
          - python3-venv
          - nginx
        state: present

    - name: Create app user
      user:
        name: "{{ app_user }}"
        system: yes
        shell: /bin/bash
        home: "{{ app_dir }}"

    - name: Create app directory
      file:
        path: "{{ app_dir }}"
        state: directory
        owner: "{{ app_user }}"
        group: "{{ app_user }}"

    - name: Copy app files
      copy:
        src: "../app/"
        dest: "{{ app_dir }}/"
        owner: "{{ app_user }}"
        group: "{{ app_user }}"

    - name: Create Python virtualenv and install dependencies
      pip:
        requirements: "{{ app_dir }}/requirements.txt"
        virtualenv: "{{ app_dir }}/venv"
        virtualenv_command: python3 -m venv

    - name: Create systemd service for Flask app
      copy:
        dest: /etc/systemd/system/flaskapp.service
        content: |
          [Unit]
          Description=Flask App
          After=network.target

          [Service]
          User={{ app_user }}
          WorkingDirectory={{ app_dir }}
          Environment="APP_VERSION=1.0.0"
          ExecStart={{ app_dir }}/venv/bin/python {{ app_dir }}/app.py
          Restart=always

          [Install]
          WantedBy=multi-user.target
      notify: Restart flaskapp

    - name: Enable and start Flask service
      systemd:
        name: flaskapp
        enabled: yes
        state: started
        daemon_reload: yes

    - name: Configure nginx reverse proxy
      template:
        src: nginx.conf.j2
        dest: /etc/nginx/sites-available/flaskapp

    - name: Enable nginx site
      file:
        src: /etc/nginx/sites-available/flaskapp
        dest: /etc/nginx/sites-enabled/flaskapp
        state: link

    - name: Remove default nginx site
      file:
        path: /etc/nginx/sites-enabled/default
        state: absent

    - name: Restart nginx
      service:
        name: nginx
        state: restarted

  handlers:
    - name: Restart flaskapp
      systemd:
        name: flaskapp
        state: restarted
        daemon_reload: yes
```

### Run it

```bash
cd ansible
ansible all -i inventory.ini -m ping        # should return pong
ansible-playbook -i inventory.ini playbook.yml
```

After 2–3 minutes, visit `http://<public_ip>` in your browser. You should see:

```json
{"message": "Hello from the DevOps tutorial!", "version": "1.0.0"}
```

Now re-run the playbook:

```bash
ansible-playbook -i inventory.ini playbook.yml
```

Notice how most tasks report `ok` rather than `changed`. **That's idempotency in action.**

### Interview angles

- **"Ansible vs Puppet vs Chef?"** Ansible is agentless (SSH-only) and uses YAML — simpler for most teams. Puppet/Chef need agents on each node, use their own DSLs, but scale better for huge fleets.
- **"What does idempotent mean in Ansible?"** Running the playbook multiple times produces the same result. Tasks check current state before acting.
- **"What's the difference between a handler and a task?"** Handlers run only when `notify`d, and only once per playbook run even if notified multiple times. Use them for restarts after config changes.
- **"Where does Terraform end and Ansible begin?"** Rule of thumb: Terraform creates the *box*, Ansible configures what's *inside* the box. Some teams use Terraform for everything via `provisioners` — but that's widely considered an anti-pattern because it mixes concerns.

---

<a name="6-github-actions"></a>
## 6. GitHub Actions — Continuous Integration

### Concept

Every time someone pushes code, GitHub Actions automatically runs a **workflow** — usually linting, tests, and builds. Fast feedback prevents broken code from merging.

**Why CI matters:** "It works on my machine" is the oldest bug in software. CI runs your tests in a clean, consistent environment, on every commit, before code gets merged.

**Key vocabulary:**
- **Workflow** — a YAML file in `.github/workflows/` that defines automation
- **Job** — a group of steps that run on the same runner
- **Step** — a single command or action
- **Runner** — the VM that executes the job (GitHub-hosted or self-hosted)
- **Action** — a reusable packaged step (like `actions/checkout@v4`)

### Hands-on

**`.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    name: Lint & Test
    runs-on: ubuntu-latest

    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"
          cache: pip

      - name: Install dependencies
        run: |
          cd app
          pip install -r requirements.txt
          pip install flake8

      - name: Lint with flake8
        run: |
          cd app
          flake8 . --max-line-length=100 --exclude=venv

      - name: Run tests
        run: |
          cd app
          pytest -v

  build-docker:
    name: Build Docker image
    needs: test      # only runs if 'test' job passes
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'   # only on main branch

    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build image
        run: |
          docker build -t flask-app:${{ github.sha }} ./app
          docker images
```

You'll also want a `Dockerfile` for the build job. Add `app/Dockerfile`:

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["python", "app.py"]
```

### Run it

```bash
# From the project root
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/<your-username>/devops-tutorial.git
git push -u origin main
```

Go to your GitHub repo → **Actions** tab. You'll see the workflow running.

### Interview angles

- **"GitHub Actions vs Jenkins?"** Actions is a managed SaaS, zero infrastructure, great for GitHub-hosted code. Jenkins is self-hosted, more flexible, better for complex/regulated environments. Actions pricing can blow up at scale; Jenkins has predictable costs but ops overhead.
- **"What's the difference between CI and CD?"** CI = Continuous Integration (merging code and running tests frequently). CD = Continuous Delivery (automatically preparing releases) or Continuous Deployment (automatically deploying to production). The distinction matters in interviews.
- **"How do you handle secrets in GitHub Actions?"** Use repository secrets (`Settings → Secrets`). Reference as `${{ secrets.MY_SECRET }}`. Never commit them. For AWS, prefer OIDC federation over long-lived keys.
- **"What's a matrix build?"** Running the same job against multiple versions (e.g., Python 3.10, 3.11, 3.12) in parallel.

---

<a name="7-jenkins"></a>
## 7. Jenkins — The Orchestrator

### Concept

Jenkins is the grandparent of CI/CD tools — older than Actions, GitLab CI, and CircleCI combined. It's still massively used in enterprises because it's self-hosted, infinitely extensible (2000+ plugins), and can orchestrate complex multi-step pipelines.

**Why companies still use Jenkins:**
- You can run it in air-gapped networks (banks, defense)
- Fine-grained control over runner hardware (GPUs, big memory boxes)
- Existing massive plugin ecosystem
- One tool can serve dozens of teams

**Key vocabulary:**
- **Jenkins master** — the controller (web UI, scheduler)
- **Agent/node** — worker that executes jobs
- **Pipeline** — a job defined as code (Jenkinsfile), usually in Groovy
- **Declarative vs. scripted pipeline** — two syntaxes; declarative is the modern choice
- **Stage** — logical chunk of a pipeline (Build, Test, Deploy)

### Hands-on — run Jenkins locally with Docker

```bash
docker run -d \
  --name jenkins \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  jenkins/jenkins:lts
```

Get the initial admin password:

```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Open `http://localhost:8080`, paste the password, install suggested plugins, create an admin user.

### The Jenkinsfile

At the **root** of your project (next to README), create `Jenkinsfile`:

```groovy
pipeline {
    agent any

    environment {
        AWS_REGION = 'eu-west-1'
        APP_VERSION = "${env.BUILD_NUMBER}"
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

        stage('Build Docker image') {
            steps {
                sh 'docker build -t flask-app:${BUILD_NUMBER} ./app'
            }
        }

        stage('Provision infrastructure') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-credentials'
                ]]) {
                    sh '''
                        cd terraform
                        terraform init
                        terraform apply -auto-approve
                        terraform output -raw public_ip > ../ansible/server_ip.txt
                    '''
                }
            }
        }

        stage('Configure & deploy') {
            steps {
                sh '''
                    cd ansible
                    SERVER_IP=$(cat server_ip.txt)
                    echo "[webservers]" > dynamic_inventory.ini
                    echo "app_server ansible_host=$SERVER_IP ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/devops-tutorial.pem" >> dynamic_inventory.ini
                    ansible-playbook -i dynamic_inventory.ini playbook.yml
                '''
            }
        }

        stage('Smoke test') {
            steps {
                sh '''
                    SERVER_IP=$(cat ansible/server_ip.txt)
                    sleep 15   # give the app time to start
                    curl -f http://$SERVER_IP/health
                '''
            }
        }
    }

    post {
        success {
            echo "Deployed version ${APP_VERSION} successfully"
        }
        failure {
            echo "Pipeline failed — check the logs"
        }
    }
}
```

### Wire it up in Jenkins UI

1. **Install plugins**: Manage Jenkins → Plugins → install `Pipeline`, `Git`, `AWS Credentials`, `Docker`.
2. **Add credentials**: Manage Jenkins → Credentials → Add → AWS Credentials (id: `aws-credentials`). Paste your AWS access key + secret.
3. **Create pipeline job**: New Item → Pipeline → name it `devops-tutorial`.
4. In the config:
   - **Pipeline definition**: "Pipeline script from SCM"
   - **SCM**: Git
   - **Repo URL**: your GitHub URL
   - **Script path**: `Jenkinsfile`
5. Click **Build Now**.

### Interview angles

- **"Declarative vs scripted pipeline?"** Declarative (the `pipeline { }` block) is structured, safer, and the modern default. Scripted is raw Groovy — more powerful but footgun-prone. Use declarative unless you have a specific reason.
- **"How do you handle Jenkins credentials?"** Store in Jenkins Credentials Manager, reference via `withCredentials`. Never hardcode.
- **"What's a Jenkins agent?"** A worker node that runs jobs. The master coordinates but delegates execution. In production, agents are ephemeral (Docker/Kubernetes-based) so each build gets a clean environment.
- **"How would you secure a Jenkins installation?"** Behind a VPN or SSO, disable anonymous access, use folder-level RBAC, keep plugins updated, run agents in isolated networks, audit logs centrally.

---

<a name="8-putting-it-all-together"></a>
## 8. Putting It All Together

### The complete flow, end-to-end

1. **Developer pushes** code to GitHub `main`
2. **GitHub Actions** runs in ~30s — lint + unit tests + Docker build
3. **Webhook** triggers Jenkins (or Jenkins polls periodically)
4. **Jenkins pipeline** runs:
   - Checkout code
   - Rerun tests (belt and braces)
   - Build Docker image tagged with build number
   - **Terraform apply** — ensures the EC2 server exists with the right security groups
   - **Ansible playbook** — pushes new code to the server, restarts the Flask service
   - Smoke test: `curl http://server/health` — if this fails, rollback
5. **Monitoring/alerting** (not covered here — Prometheus/Grafana/Datadog would go here)

### The tradeoffs worth understanding

**Why not just use Terraform for everything (with provisioners)?** Terraform provisioners are a last resort. They aren't idempotent, don't handle partial failures well, and mix "what to create" with "how to configure it". Keeping Terraform for infra and Ansible for config respects the **separation of concerns** principle.

**Why not use Ansible for provisioning (`ec2_instance` module)?** You can — Ansible has cloud modules. But Ansible's state tracking is weaker than Terraform's. You lose the plan/apply workflow and the dependency graph.

**Why not just GitHub Actions with no Jenkins?** Totally valid for most teams. Use GH Actions for everything unless you specifically need Jenkins features.

---

<a name="9-interview-prep-cheat-sheet"></a>
## 9. Interview Prep Cheat Sheet

### The "explain your pipeline" question (asked in ~every interview)

Have a 60-second story ready:

> *"In my setup, a developer pushes to GitHub. GitHub Actions immediately runs linting and unit tests for fast feedback. On merge to main, Jenkins takes over — it builds a Docker image, runs Terraform to ensure the EC2 infrastructure matches our desired state, then runs an Ansible playbook to configure the server and deploy the new version. Finally it smoke-tests the deployment. Terraform handles infrastructure, Ansible handles configuration, GitHub Actions handles fast CI, Jenkins orchestrates the full delivery pipeline."*

### Concepts you must be able to explain

| Concept | One-line explanation |
|---------|---------------------|
| **Idempotency** | Running the same operation twice produces the same result |
| **Immutable infrastructure** | Servers are never changed in place — you replace them |
| **Blue/green deployment** | Keep old version (blue) running while deploying new version (green), then switch traffic |
| **Canary release** | Send a small % of traffic to the new version first, ramp up if metrics stay healthy |
| **Rollback strategy** | Keep the last working artifact, have a one-button path back |
| **IaC (Infrastructure as Code)** | Infrastructure defined in version-controlled files, not clicked together |
| **GitOps** | Git is the source of truth; agents auto-apply changes from git (ArgoCD, Flux) |
| **Secrets management** | Never commit secrets; use Vault, AWS Secrets Manager, or CI-provider secret stores |
| **Drift** | When real infrastructure diverges from what your IaC says. Detected by `terraform plan`. |

### Common trap questions

**Q: "Terraform or Ansible for provisioning?"**
A: Terraform. It's designed for infrastructure with proper state tracking, a dependency graph, and plan/apply. Ansible *can* provision but is better suited to configuration.

**Q: "What happens if two people run `terraform apply` at the same time?"**
A: Without state locking, the state file can corrupt. Production setups use remote state (S3) with locking (DynamoDB) so only one apply runs at a time.

**Q: "How would you deploy with zero downtime?"**
A: Options: rolling deployment (update instances one by one behind a load balancer), blue/green (two full environments, swap), or canary (gradual traffic shift). Pick based on risk tolerance and infrastructure cost.

**Q: "How do you roll back a bad deployment?"**
A: Ideal: immutable artifacts (Docker images), previous version kept warm, load balancer swaps back to old target group. Worst case: redeploy the previous Git SHA.

**Q: "What's the biggest DevOps challenge you'd expect?"**
A: Cultural more than technical. Getting dev and ops to share ownership of reliability, getting teams to trust automation, breaking down silos. The tools are the easy part.

### Things you should *not* say in interviews

- "DevOps is a role" — it's a practice/culture. A "DevOps Engineer" is really an SRE or Platform Engineer.
- "We push to prod on Fridays" — even jokingly. (Modern teams push any day, with confidence from automation, but culturally it's a red flag.)
- "I just YOLO the terraform apply" — always `plan` first.

---

## What to do next

Once you've walked through this tutorial end-to-end:

1. **Destroy your infra** (`terraform destroy`) so you don't get billed
2. **Add a new feature to the app**, push it, watch the pipeline
3. **Break something on purpose** — rename a Terraform resource, write a failing test — and see how each tool reports failure
4. **Extend it**:
   - Swap Flask for FastAPI, or add a Postgres database (RDS via Terraform)
   - Add Prometheus/Grafana for monitoring
   - Replace EC2 with ECS or EKS
   - Introduce HashiCorp Vault for secrets
   - Explore GitHub Actions alternatives: GitLab CI, CircleCI
5. **Get certified**: Terraform Associate and AWS Solutions Architect Associate are the most job-relevant certs for entry-level DevOps roles.

Good luck with the interviews.
