---
name: repo-deps-automate
description: This skill guides agents in automating dependency updates across multiple programming ecosystems using Dependabot or similar tools. It covers ecosystem detection, configuration generation, and maintenance strategies.
---

# Dependency Update Automation Skill

## Overview
This skill guides agents in automating dependency updates across multiple programming ecosystems using Dependabot or similar tools. It covers ecosystem detection, configuration generation, and maintenance strategies.

## Core Capabilities

### 1. Ecosystem Detection

#### Primary Detection Methods
```bash
# Node.js/JavaScript/TypeScript
find . -name "package.json" -o -name "yarn.lock" -o -name "pnpm-lock.yaml" -o -name "package-lock.json"

# Python
find . -name "requirements.txt" -o -name "pyproject.toml" -o -name "Pipfile" -o -name "poetry.lock" -o -name "setup.py"

# Java/Kotlin
find . -name "pom.xml" -o -name "build.gradle" -o -name "build.gradle.kts" -o -name "gradle.properties"

# Go
find . -name "go.mod" -o -name "go.sum"

# Rust
find . -name "Cargo.toml" -o -name "Cargo.lock"

# PHP
find . -name "composer.json" -o -name "composer.lock"

# Ruby
find . -name "Gemfile" -o -name "Gemfile.lock" -o -name "*.gemspec"

# .NET
find . -name "*.csproj" -o -name "*.fsproj" -o -name "*.vbproj" -o -name "packages.config" -o -name "Directory.Build.props"

# Docker
find . -name "Dockerfile" -o -name "docker-compose.yml" -o -name "docker-compose.yaml"

# GitHub Actions
find . -path ".github/workflows/*.yml" -o -path ".github/workflows/*.yaml"
```

#### Ecosystem Identification Matrix

| Ecosystem | Package Manager | Manifest Files | Lock Files | Config Files |
|-----------|----------------|----------------|------------|--------------|
| **Node.js** | npm, yarn, pnpm | package.json | package-lock.json, yarn.lock, pnpm-lock.yaml | .npmrc, .yarnrc.yml |
| **Python** | pip, pipenv, poetry, conda | requirements.txt, pyproject.toml, Pipfile, setup.py | Pipfile.lock, poetry.lock | pip.conf, pyproject.toml |
| **Java** | maven, gradle | pom.xml, build.gradle, build.gradle.kts | gradle.lockfile | settings.xml, gradle.properties |
| **Go** | go modules | go.mod | go.sum | go.work |
| **Rust** | cargo | Cargo.toml | Cargo.lock | .cargo/config.toml |
| **PHP** | composer | composer.json | composer.lock | composer.json |
| **Ruby** | bundler, gem | Gemfile, *.gemspec | Gemfile.lock | .bundle/config |
| **C#/.NET** | nuget, paket | *.csproj, packages.config, Directory.Build.props | packages.lock.json | nuget.config |
| **Docker** | docker | Dockerfile, docker-compose.yml | - | .dockerignore |
| **GitHub Actions** | - | .github/workflows/*.yml | - | - |

### 2. Dependabot Configuration Generation

#### Base Template Structure
```yaml
# .github/dependabot.yml
version: 2
updates: []
```

#### Ecosystem-Specific Configurations

**Node.js/JavaScript/TypeScript:**
```yaml
- package-ecosystem: "npm"
  directory: "/"
  schedule:
    interval: "weekly"
    day: "monday"
    time: "09:00"
  open-pull-requests-limit: 5
  reviewers:
    - "@your-team"
  assignees:
    - "@maintainer"
  commit-message:
    prefix: "⬆️ "
    include: "scope"
  groups:
    development-dependencies:
      dependency-type: "development"
    production-dependencies:
      dependency-type: "production"
```

**Python:**
```yaml
- package-ecosystem: "pip"
  directory: "/"
  schedule:
    interval: "weekly"
  target-branch: "develop"
  allow:
    - dependency-type: "direct"
    - dependency-type: "indirect"
  ignore:
    - dependency-name: "django"
      versions: [">=3.0.0"]
```

**Java (Maven):**
```yaml
- package-ecosystem: "maven"
  directory: "/"
  schedule:
    interval: "weekly"
  insecure-external-code-execution: "allow"
```

**Java (Gradle):**
```yaml
- package-ecosystem: "gradle"
  directory: "/"
  schedule:
    interval: "weekly"
```

**Go:**
```yaml
- package-ecosystem: "gomod"
  directory: "/"
  schedule:
    interval: "weekly"
  target-branch: "main"
```

**Rust:**
```yaml
- package-ecosystem: "cargo"
  directory: "/"
  schedule:
    interval: "weekly"
```

**PHP (Composer):**
```yaml
- package-ecosystem: "composer"
  directory: "/"
  schedule:
    interval: "weekly"
```

**Ruby:**
```yaml
- package-ecosystem: "bundler"
  directory: "/"
  schedule:
    interval: "weekly"
```

**.NET/NuGet:**
```yaml
- package-ecosystem: "nuget"
  directory: "/"
  schedule:
    interval: "weekly"
```

**Docker:**
```yaml
- package-ecosystem: "docker"
  directory: "/"
  schedule:
    interval: "weekly"
```

**GitHub Actions:**
```yaml
- package-ecosystem: "github-actions"
  directory: "/"
  schedule:
    interval: "weekly"
  commit-message:
    prefix: "🔧 "
```

### 3. Detection Algorithm

#### Step-by-Step Process

1. **Scan Repository Structure**
   ```bash
   # Create comprehensive file inventory
   find . -type f \( -name "*.json" -o -name "*.toml" -o -name "*.yaml" -o -name "*.yml" -o -name "*.xml" -o -name "*.lock" -o -name "*.gradle*" -o -name "Dockerfile*" -o -name "Gemfile*" -o -name "Pipfile*" -o -name "requirements*.txt" -o -name "setup.py" -o -name "go.mod" -o -name "Cargo.toml" -o -name "*.csproj" -o -name "composer.json" \) | head -50
   ```

2. **Identify Root vs Subdirectories**
   ```bash
   # Map directories with package managers
   for ecosystem_file in package.json pyproject.toml pom.xml build.gradle go.mod Cargo.toml composer.json Gemfile; do
     find . -name "$ecosystem_file" -exec dirname {} \; | sort | uniq
   done
   ```

3. **Determine Package Manager Context**
   ```bash
   # Node.js package manager detection
   if [ -f "yarn.lock" ]; then echo "yarn"
   elif [ -f "pnpm-lock.yaml" ]; then echo "pnpm"
   elif [ -f "package-lock.json" ]; then echo "npm"
   fi
   
   # Python package manager detection
   if [ -f "poetry.lock" ]; then echo "poetry"
   elif [ -f "Pipfile" ]; then echo "pipenv"
   elif [ -f "requirements.txt" ]; then echo "pip"
   fi
   ```

### 4. Advanced Configuration Strategies

#### Monorepo Support
```yaml
# Multiple directories for the same ecosystem
- package-ecosystem: "npm"
  directory: "/frontend"
  schedule:
    interval: "weekly"
    
- package-ecosystem: "npm"
  directory: "/backend"
  schedule:
    interval: "weekly"
    
- package-ecosystem: "npm"
  directory: "/packages/shared"
  schedule:
    interval: "weekly"
```

#### Conditional Updates
```yaml
# Security-only updates for stable branches
- package-ecosystem: "npm"
  directory: "/"
  schedule:
    interval: "daily"
  target-branch: "main"
  update-types:
    - "security"
    
# All updates for development
- package-ecosystem: "npm"
  directory: "/"
  schedule:
    interval: "weekly"
  target-branch: "develop"
```

#### Dependency Grouping
```yaml
# Group related dependencies
- package-ecosystem: "npm"
  directory: "/"
  schedule:
    interval: "weekly"
  groups:
    react-ecosystem:
      patterns:
        - "react*"
        - "@types/react*"
    testing-framework:
      patterns:
        - "jest"
        - "@testing-library/*"
        - "vitest"
    build-tools:
      patterns:
        - "vite*"
        - "webpack*"
        - "rollup*"
```

### 5. Implementation Commands

#### Generate Dependabot Config
```bash
# Create basic structure
mkdir -p .github
cat > .github/dependabot.yml << 'EOF'
version: 2
updates: []
EOF

# Add ecosystem-specific configurations based on detection
# (Implementation varies based on detected ecosystems)
```

#### Ecosystem Detection Script
```bash
#!/bin/bash
detect_ecosystems() {
    local ecosystems=()
    
    # Node.js detection
    if [ -f "package.json" ]; then
        ecosystems+=("npm")
    fi
    
    # Python detection
    if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "Pipfile" ]; then
        ecosystems+=("pip")
    fi
    
    # Java detection
    if [ -f "pom.xml" ]; then
        ecosystems+=("maven")
    elif find . -name "build.gradle*" -o -name "gradle.properties" | grep -q .; then
        ecosystems+=("gradle")
    fi
    
    # Go detection
    if [ -f "go.mod" ]; then
        ecosystems+=("gomod")
    fi
    
    # Rust detection
    if [ -f "Cargo.toml" ]; then
        ecosystems+=("cargo")
    fi
    
    # PHP detection
    if [ -f "composer.json" ]; then
        ecosystems+=("composer")
    fi
    
    # Ruby detection
    if [ -f "Gemfile" ] || find . -name "*.gemspec" | grep -q .; then
        ecosystems+=("bundler")
    fi
    
    # .NET detection
    if find . -name "*.csproj" -o -name "packages.config" | grep -q .; then
        ecosystems+=("nuget")
    fi
    
    # Docker detection
    if [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
        ecosystems+=("docker")
    fi
    
    # GitHub Actions detection
    if find .github/workflows -name "*.yml" -o -name "*.yaml" 2>/dev/null | grep -q .; then
        ecosystems+=("github-actions")
    fi
    
    printf '%s\n' "${ecosystems[@]}"
}
```

### 6. Best Practices

#### Configuration Recommendations
- **Schedule**: Weekly updates on Monday mornings
- **PR Limits**: Max 5 open PRs per ecosystem
- **Grouping**: Group related dependencies (frameworks, testing, build tools)
- **Targeting**: Use development branches for regular updates, main for security
- **Commit Messages**: Use conventional commit prefixes with emoji
- **Reviews**: Assign team leads for critical dependencies

#### Security Considerations
- Enable security-only updates for production branches
- Set up notifications for high-severity vulnerabilities
- Configure auto-merge for patch-level security updates
- Exclude beta/alpha versions from automatic updates

#### Performance Optimization
- Stagger update schedules across ecosystems
- Use dependency grouping to reduce PR noise
- Set appropriate open-pull-request limits
- Configure ignore rules for known problematic packages

### 7. Usage Instructions

1. **Run Ecosystem Detection**: Execute detection script to identify all package managers
2. **Generate Base Config**: Create dependabot.yml with detected ecosystems
3. **Customize Schedule**: Adjust update frequency based on project needs
4. **Configure Groups**: Set up logical dependency groupings
5. **Set Branch Strategy**: Define target branches for different update types
6. **Enable Notifications**: Configure team notifications and reviewers
7. **Monitor and Adjust**: Regularly review and optimize configuration

This skill enables agents to automatically detect project ecosystems and generate appropriate Dependabot configurations for comprehensive dependency management across diverse technology stacks.