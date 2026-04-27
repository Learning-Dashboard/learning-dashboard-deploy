# Learning Dashboard - Data Infrastructure Integration
## Integration of a New Data Infrastructure into the Learning Dashboard

This repository contains the complete infrastructure of the Learning Dashboard ecosystem, including all dockerized services, databases, webhooks, and administration tools.

## 📋 Table of Contents

- [System Architecture](#system-architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Included Services](#included-services)
- [Usage](#usage)
- [Development](#development)
- [Troubleshooting](#troubleshooting)

## 🏗️ System Architecture

The ecosystem consists of **7 interconnected services** that work together to provide a complete analysis and management system for the Learning Dashboard:

```
┌──────────────────────────────────────────────────────────────────┐
│                     LEARNING DASHBOARD ECOSYSTEM                 │
│                                                                  │
│  ┌─────────────────┐                        ┌─────────────────┐  │
│  │  Admin Tool     │──────────┐             │  LD Frontend    │  │
│  │  Frontend       │          │             │  (Tomcat UI)    │  │
│  │  (React+Vite)   │          │             └───────┬─────────┘  │
│  └────────┬────────┘          │                     │            │
│           │                   │                     │            │
│           ├──────────────┐    │                     │            │
│           │              │    │                     │            │
│           ▼              ▼    ▼                     ▼            │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐   │
│  │  Admin Tool     │  │   LD Eval       │  │   Tomcat        │   │
│  │  Backend        │  │   (Metrics &    │  │   (LD Core)     │   │
│  │  (Spring Boot)  │  │   Evaluation)   │  └────────┬────────┘   │
│  └────────┬────────┘  └────────┬────────┘           │            │
│           │                    │                    │            │
│           │                    │                    │            │
│           │                    │                    │            │
│           ▼                    │                    ▼            │
│  ┌─────────────────┐           │           ┌─────────────────┐   │
│  │   Tomcat        │           │           │  PostgreSQL     │   │
│  │   (LD Backend)  │◄──────────┘           │  (SQL Data)     │   │
│  └────────┬────────┘                       └─────────────────┘   │
│           │                                                      │
│           ▼                                ┌─────────────────┐   │
│  ┌─────────────────┐                       │   MongoDB       │   │
│  │  PostgreSQL     │             ┌────────►│  (Metrics &     │   │
│  │  (Projects,     │             │         │   Events)       │   │
│  │   Students)     │             │         └─────────▲───────┘   │
│  └─────────────────┘             │                   │           │
│                                  │                   │           │
│                         ┌────────┴────────┐          │           │
│                         │   LD Eval       │──────────┘           │
│                         │   (Process &    │                      │
│                         │    Store)       │                      │
│                         └────────▲────────┘                      │
│                                  │                               │
│                         ┌────────┴────────┐                      │
│                         │   LD Connect    │                      │
│                         │   (Webhooks)    │                      │
│                         └────────▲────────┘                      │
│                                  │                               │
│  ┌───────────────────────────────┴───────────────────────────┐   │
│  │                    EXTERNAL SOURCES                       │   │
│  │                                                           │   │
│  │  ┌──────────────┐              ┌──────────────┐           │   │
│  │  │   GitHub     │              │    Taiga     │           │   │
│  │  │  (Webhooks)  │              │  (Webhooks)  │           │   │
│  │  └──────────────┘              └──────────────┘           │   │
│  └───────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

### Data Flow

**1. Event Capture (LD Connect):**
   - Receives webhooks from **GitHub** (push, pull requests)
   - Receives webhooks from **Taiga** (tasks, milestones)
   - Notifies **LD Eval** for processing

**2. Metrics Processing (LD Eval):**
   - Evaluates received changes
   - Calculates metrics and quality factors
   - Stores results in **MongoDB**

**3. Main Visualization (LD Frontend):**
   - Displays metrics and factors from **MongoDB**
   - Displays project data from **PostgreSQL**
   - Interface accessible via **Tomcat**

**4. Administration (Admin Tool):**
   - **Frontend**: React interface for managing teams
   - **Backend**: Spring Boot API for administrative operations
   - Connects to **Tomcat (LD Backend)** to access data
   - Connects directly to **LD Eval** for certain queries
   - All backed by **PostgreSQL**

## 📦 Prerequisites

- **Docker Desktop** (Windows/Mac) or Docker Engine (Linux)
- **Docker Compose** v2.0 or higher
- **Git** to clone the repository and its submodules
- **Available ports**: 5000, 5001, 5432, 5433, 8080, 8888, 27017, 3000

## 🚀 Quick Start

### 1. Clone the repository with its submodules

```bash
git clone --recurse-submodules https://github.com/Learning-Dashboard/learning-dashboard-deploy.git
cd learning-dashboard-deploy
```

This command downloads the main repository and also automatically initializes the required submodules.

### 2. Initialize submodules if you already cloned without `--recurse-submodules`

If you already ran `git clone` without including the submodules, you can download them afterwards with:

```bash
git submodule update --init --recursive
```

### 3. Configure environment variables

Copy the example file and edit it with your values:

```bash
cp .env.template .env
```

Edit the `.env` file with your settings (see [Configuration](#configuration)).

### 4. Start all services

```bash
docker compose up -d
```

Use `docker compose` **without a hyphen**. That is the current Docker Compose v2 syntax.

### 5. Verify everything is working

```bash
docker compose ps
```

You should see all services with a "Up" status.

## ⚙️ Configuration

### Main `.env` file

The `.env` file at the root contains **all centralized configuration**:

```env
# URLs de túneles ngrok (cambiar según sea necesario)
NGROK_LD_URL=https://xxxx.ngrok-free.app
NGROK_LDCONNECT_URL=https://yyyy.ngrok-free.app

# Taiga Configuration
TAIGA_API_URL=https://zzzz.ngrok-free.dev/api/v1
TAIGA_AUTH_URL=https://api.taiga.io/api/v1
TAIGA_USERNAME=tu_usuario
TAIGA_PASSWORD=tu_password

# GitHub Configuration
GITHUB_TOKEN=ghp_xxxxxxxxxxxxx

# MongoDB Configuration
MONGO_USER=admin
MONGO_PASSWORD=3LnS985q7tR9

# PostgreSQL Configuration
DB_USER=postgres
DB_PASSWORD=example
```

**Important**:
- `TAIGA_API_URL` points to the FIB Taiga ngrok (for queries)
- `TAIGA_AUTH_URL` always points to public Taiga (for authentication)
- **Never** commit the `.env` file to Git (it is listed in `.gitignore`)

## 🔧 Included Services

| Service | Port | Description | Technology |
|---------|------|-------------|------------|
| **Admin Tool Frontend** | 3000 | Administration interface | React + Vite + Nginx |
| **Admin Tool Backend** | 8080 | Administration API | Spring Boot 3.5.6 (Java 17) |
| **LD Connect** | 5000 | GitHub/Taiga webhook management | Python 3.9 + Flask |
| **LD Eval** | 5001 | Evaluation and metrics | Python 3.9 + Flask |
| **Tomcat (LD Core)** | 8888 | Main Learning Dashboard | Java + Tomcat 9 |
| **PostgreSQL** | 5433 | Main database | PostgreSQL 9.6 |
| **MongoDB** | 27017 | Events database | MongoDB 6.0 |

## 📖 Usage

### Accessing the interfaces

- **Admin Tool**: http://localhost:3000
- **Learning Dashboard**: http://localhost:8888
- **MongoDB Compass**: localhost:27017 (user: `admin`, password: `3LnS985q7tR9`)

### Importing teams from Excel

1. Go to the Admin Tool at http://localhost:3000
2. Navigate to the "Import Teams" section
3. Upload an Excel file with the specified format
4. The system will validate the projects in Taiga and GitHub
5. Teams will be created automatically in the LD

### Webhooks

GitHub and Taiga webhooks automatically send events to LD Connect when changes occur:

- **GitHub webhook URL**: `{NGROK_LDCONNECT_URL}/webhook/github?prj=project-name`
- **Taiga webhook URL**: `{NGROK_LDCONNECT_URL}/webhook/taiga?prj=project-name`

## 🛠️ Development

### Rebuild a specific service

```bash
# Admin Tool Backend
docker compose build admintool_backend
docker compose up -d admintool_backend

# Admin Tool Frontend
docker compose build admintool_frontend
docker compose up -d admintool_frontend

# LD Connect
docker compose build ld_connect
docker compose up -d ld_connect
```

### View logs for a service

```bash
docker logs -f LDConnect
docker logs -f ld_admintool_backend
docker logs -f admintool_frontend
```

### Restart the entire system

```bash
docker compose down
docker compose up -d
```

### Access a container's terminal

```bash
docker exec -it LDConnect bash
docker exec -it ld_admintool_backend sh
```

## 🐛 Troubleshooting

### Containers won't start

1. Verify that Docker Desktop is running
2. Check that the required ports are not already in use:
   ```bash
   netstat -ano | findstr :8080
   netstat -ano | findstr :3000
   ```
3. Review the logs:
   ```bash
   docker compose logs
   ```

### MongoDB authentication error

If you see `Unauthorized` errors in the logs:

1. Verify that the `.env` file has the correct credentials
2. Restart the services:
   ```bash
   docker compose restart ld_connect ld_eval
   ```

### 401 error on Taiga API

If you see `401 Unauthorized` when querying milestones:

- **Cause**: The FIB Taiga ngrok requires authentication
- **Solution**: Verify that `TAIGA_API_URL` points to the correct ngrok and that the ngrok server has authentication disabled

### Webhooks not working

1. Verify that ngrok is running and the URL is accessible
2. Check that the webhook in GitHub/Taiga has the correct URL
3. Review the LD Connect logs:
   ```bash
   docker logs LDConnect --tail 50
   ```

### Admin Tool cannot connect to the backend

1. Verify that the backend is running:
   ```bash
   docker ps | grep admintool
   ```
2. Check the Nginx configuration in the frontend
3. Review the backend logs:
   ```bash
   docker logs ld_admintool_backend
   ```

## 📚 Additional Documentation
- [LD_Connect_Event/README.md](LD_Connect_Event/README.md) - LD Connect documentation
- [LD_Eval_Event/README.md](LD_Eval_Event/README.md) - LD Eval documentation

## 🔐 Security

- **Never** commit the `.env` file to Git
- Use `.env.template` as a reference to create your local `.env`
- Tokens and passwords should be regenerated in production
- MongoDB and PostgreSQL are only accessible from `127.0.0.1` (localhost)

## 📝 Notes for the Next Person

1. **Ngrok URLs**: Ngrok tunnels change every time ngrok is restarted. Update `NGROK_LD_URL` and `NGROK_LDCONNECT_URL` in the `.env` when necessary.

2. **FIB Taiga**: If its ngrok changes, update `TAIGA_API_URL` in the `.env`.

3. **Git Submodules**: The repositories inside learning-dashboard-infrastructure (LD-learning-dashboard, ld_admintool, etc.) are independent repositories. You can commit and push in each one separately.

4. **Rebuilding containers**: If you change Python or Java code, you need to rebuild the corresponding container with `docker compose build <service>`.

5. **Database**: PostgreSQL and MongoDB data is stored in Docker volumes. It persists even if you restart the containers.

## Authors
