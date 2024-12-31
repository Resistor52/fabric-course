# Fabric Course

Welcome to the Fabric Course! This environment is pre-configured with everything you need to get started.

## Environment Setup

Your environment includes:
- VS Code (code-server) web IDE
- Go programming language
- Fabric CLI tool
- Ollama AI with Mistral model

## Getting Started

1. Open a terminal (Terminal → New Terminal)
2. Verify Fabric is working:
   ```bash
   fabric --version
   ```

3. Test the AI integration:
   ```bash
   echo "Hello" | fabric -p ai
   ```

## Course Content

### Module 1: Introduction to Fabric
- What is Fabric?
- Understanding AI-powered workflows
- Basic command structure

### Module 2: Working with Patterns
- Built-in patterns
- Creating custom patterns
- Pattern composition

### Module 3: AI Integration
- Working with Ollama
- Using different models
- Best practices for prompts

### Module 4: Advanced Topics
- Custom pattern development
- Integration with other tools
- Performance optimization

## Exercises

1. Basic Pattern Usage
   ```bash
   # Try these patterns
   echo "Give me 5 ideas for securing SSH" | fabric -p security
   echo "Explain quantum computing" | fabric -p explain
   ```

2. Pattern Exploration
   ```bash
   # List available patterns
   fabric -l
   
   # Get pattern details
   fabric -p security -i
   ```

## Additional Resources

- [Fabric Documentation](https://github.com/danielmiessler/fabric)
- [Go Documentation](https://golang.org/doc/)
- [VS Code Shortcuts](https://code.visualstudio.com/docs/getstarted/keybindings)
- [Ollama Models](https://ollama.ai/library)

## Getting Help

If you need assistance:
1. Check the Fabric documentation
2. Use the `fabric -h` command
3. Ask the AI for help: `echo "How do I use fabric?" | fabric -p ai` 