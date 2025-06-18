#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Onezipp N8N Cluster - Git Repository Setup ===${NC}"
echo ""

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${RED}Git is not installed. Please install git first.${NC}"
    exit 1
fi

# Initialize git repository
if [ ! -d .git ]; then
    echo -e "${YELLOW}Initializing git repository...${NC}"
    git init
    echo -e "${GREEN}✓ Git repository initialized${NC}"
else
    echo -e "${GREEN}✓ Git repository already exists${NC}"
fi

# Create project structure
echo -e "${YELLOW}Creating project structure...${NC}"
mkdir -p docs examples workflows

# Move setup script to root if it exists
if [ -f onezipp-setup.sh ]; then
    mv onezipp-setup.sh setup.sh
fi

# Create example workflow directory
if [ ! -f workflows/ai-qa-example.json ]; then
    echo -e "${YELLOW}Adding example workflow...${NC}"
    # The workflow JSON will be added manually
fi

# Add all files
echo -e "${YELLOW}Adding files to git...${NC}"
git add .

# Create initial commit
echo -e "${YELLOW}Creating initial commit...${NC}"
git commit -m "Initial commit: Onezipp N8N Cluster setup script with AI starter kit integration" 2>/dev/null || echo -e "${GREEN}✓ Already committed${NC}"

# Get GitHub username
echo ""
read -p "Enter your GitHub username: " GITHUB_USER
if [ -z "$GITHUB_USER" ]; then
    echo -e "${RED}GitHub username is required${NC}"
    exit 1
fi

# Repository name
read -p "Enter repository name [onezipp-n8n-cluster]: " REPO_NAME
REPO_NAME=${REPO_NAME:-onezipp-n8n-cluster}

# Check if remote already exists
if git remote get-url origin &> /dev/null; then
    echo -e "${YELLOW}Remote 'origin' already exists. Do you want to change it? (y/N)${NC}"
    read -p "" CHANGE_REMOTE
    if [[ "$CHANGE_REMOTE" =~ ^[Yy]$ ]]; then
        git remote remove origin
    else
        echo -e "${GREEN}Keeping existing remote${NC}"
        SKIP_REMOTE=true
    fi
fi

if [ -z "$SKIP_REMOTE" ]; then
    # Add remote
    echo -e "${YELLOW}Adding GitHub remote...${NC}"
    git remote add origin "https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
    echo -e "${GREEN}✓ Remote added${NC}"
fi

# Create README if it doesn't exist
if [ ! -f README.md ]; then
    echo -e "${RED}README.md not found. Please add it before pushing.${NC}"
fi

# Instructions for creating repo
echo ""
echo -e "${BLUE}=== Next Steps ===${NC}"
echo ""
echo -e "${YELLOW}1. Create a new repository on GitHub:${NC}"
echo -e "   Visit: ${GREEN}https://github.com/new${NC}"
echo -e "   Repository name: ${GREEN}${REPO_NAME}${NC}"
echo -e "   Description: ${GREEN}Production-ready N8N cluster setup with AI capabilities, Caddy SSL, and queue mode${NC}"
echo -e "   Make it ${GREEN}public${NC}"
echo -e "   ${RED}DO NOT${NC} initialize with README, .gitignore, or license"
echo ""
echo -e "${YELLOW}2. After creating the repository on GitHub, push your code:${NC}"
echo -e "   ${GREEN}git branch -M main${NC}"
echo -e "   ${GREEN}git push -u origin main${NC}"
echo ""
echo -e "${YELLOW}3. Optional: Add topics to your repository:${NC}"
echo -e "   - n8n"
echo -e "   - automation"
echo -e "   - ai"
echo -e "   - docker"
echo -e "   - self-hosted"
echo -e "   - workflow-automation"
echo -e "   - ollama"
echo -e "   - caddy"
echo ""
echo -e "${BLUE}Repository URL will be: ${GREEN}https://github.com/${GITHUB_USER}/${REPO_NAME}${NC}"
echo ""

# Create a quick push script
cat > push.sh << 'EOF'
#!/bin/bash
git add .
git commit -m "$1"
git push origin main
EOF
chmod +x push.sh

echo -e "${GREEN}✓ Created push.sh for quick commits${NC}"
echo -e "  Usage: ${YELLOW}./push.sh \"Your commit message\"${NC}"
echo ""
