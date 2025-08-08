# Changelog

All notable changes to the Cursor CLI Plugin for Neovim will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-08-08

### Added
- Initial release of Cursor CLI Plugin for Neovim
- AI Chat Interface (`:CursorChat`)
- Intelligent Code Editing with diff preview (`:CursorEdit`)
- Code Generation from natural language (`:CursorGenerate`)
- Code Explanation and documentation (`:CursorExplain`)
- Automated Code Review (`:CursorReview`)
- Performance Optimization suggestions (`:CursorOptimize`)
- Error Detection and Fixing (`:CursorFix`)
- Smart Refactoring with interactive menu (`:CursorRefactor`)
- Streaming responses with timeout handling
- Context-aware prompts with file type detection
- Interactive diff previews for code changes
- Comprehensive Vim help documentation
- MIT License
- Autoload functionality for better performance
- Support for multiple AI models (sonnet-4, gpt-5, etc.)
- Proper error handling and user feedback
- Compatible with vim-plug, packer.nvim, and lazy.nvim

### Technical Details
- VimScript implementation for maximum compatibility
- Autoload functions for efficient loading
- Streaming JSON parsing for real-time responses
- Shell script integration for cursor-agent CLI
- Comprehensive error handling and validation
- Markdown syntax highlighting for AI responses
- Interactive confirmation prompts for code changes 