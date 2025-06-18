#!/bin/bash

# Create Onezipp N8N Cluster Repository
# This script creates all necessary files for the repository

set -e

echo "🚀 Creating Onezipp N8N Cluster Repository Structure..."

# Create directories
echo "📁 Creating directories..."
mkdir -p docs workflows examples

# Download the main setup script (you'll need to add this manually)
echo "📝 Creating setup.sh..."
echo "⚠️  Note: Add the main setup.sh script content manually"
touch setup.sh
chmod +x setup.sh

# Create .gitignore
echo "📝 Creating .gitignore..."
cat > .gitignore << 'EOF'
# Environment files
.env
.env.local
.env.production
*.env

# Configuration files with secrets
config-summary.txt
*-credentials.txt
*-passwords.txt

# Docker volumes
postgres_storage/
redis_storage/
ollama_storage/
qdrant_storage/
n8n_storage/
caddy_data/
caddy_config/

# Logs
*.log
logs/
docker-logs/

# OS files
.DS_Store
Thumbs.db

# Editor files
.vscode/
.idea/
*.swp
*.swo
*~

# Backup files
*.bak
*.backup
*.old

# Temporary files
*.tmp
*.temp
/tmp/

# SSL certificates
*.pem
*.crt
*.key
certificates/

# Node modules
node_modules/

# Python
__pycache__/
*.py[cod]
*$py.class
venv/
.Python

# Test files
test/
tests/
*.test

# Archives
*.zip
*.tar.gz
*.tar
*.gz
EOF

# Create LICENSE
echo "📝 Creating LICENSE..."
cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2024 Onezipp N8N Cluster

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

# Create README.md placeholder
echo "📝 Creating README.md placeholder..."
echo "# Onezipp N8N Cluster" > README.md
echo "" >> README.md
echo "⚠️ Note: Add the full README.md content manually" >> README.md

# Create documentation files
echo "📝 Creating documentation files..."
echo "# Quick Start Guide" > docs/QUICK_START.md
echo "⚠️ Note: Add the full quick start guide content manually" >> docs/QUICK_START.md

echo "# Troubleshooting Guide" > docs/TROUBLESHOOTING.md
echo "⚠️ Note: Add the full troubleshooting guide content manually" >> docs/TROUBLESHOOTING.md

# Create example workflow placeholder
echo "📝 Creating workflow example..."
echo "{}" > workflows/ai-qa-example.json
echo "⚠️ Note: Add the full workflow JSON manually to workflows/ai-qa-example.json"

# Create docker compose example
echo "📝 Creating Docker Compose example..."
echo "# Custom Docker Compose Examples" > examples/docker-compose.custom.yml
echo "⚠️ Note: Add the full custom docker-compose content manually"

# Create setup-git.sh
echo "📝 Creating setup-git.sh..."
touch setup-git.sh
chmod +x setup-git.sh
echo "⚠️ Note: Add the setup-git.sh content manually"

# Create push.sh helper
echo "📝 Creating push.sh helper..."
cat > push.sh << 'EOF'
#!/bin/bash
git add .
git commit -m "$1"
git push origin main
EOF
chmod +x push.sh

# Summary
echo ""
echo "✅ Repository structure created!"
echo ""
echo "📁 Directory structure:"
echo "   onezipp-n8n-cluster/"
echo "   ├── setup.sh"
echo "   ├── README.md"
echo "   ├── LICENSE"
echo "   ├── .gitignore"
echo "   ├── setup-git.sh"
echo "   ├── push.sh"
echo "   ├── docs/"
echo "   │   ├── QUICK_START.md"
echo "   │   └── TROUBLESHOOTING.md"
echo "   ├── workflows/"
echo "   │   └── ai-qa-example.json"
echo "   └── examples/"
echo "       └── docker-compose.custom.yml"
echo ""
echo "⚠️  Important: You need to manually add the content for:"
echo "   1. setup.sh (main installation script)"
echo "   2. README.md (full documentation)"
echo "   3. docs/QUICK_START.md"
echo "   4. docs/TROUBLESHOOTING.md"
echo "   5. workflows/ai-qa-example.json"
echo "   6. examples/docker-compose.custom.yml"
echo "   7. setup-git.sh"
echo ""
echo "📝 Next steps:"
echo "   1. Add the missing content to all files"
echo "   2. Run: git init"
echo "   3. Run: git add ."
echo "   4. Run: git commit -m 'Initial commit'"
echo "   5. Create repository on GitHub"
echo "   6. Push to GitHub"
echo ""
