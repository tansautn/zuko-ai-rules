---
description: Translate documentation from Vietnamese to English
---

This workflow provides a structured approach for translating project documentation from Vietnamese to English while maintaining all formatting and technical accuracy.

1. **Identify Target Files**: 
   - Scan the `docs/` directory or specific target directories for Markdown files.
   - Look for files containing Vietnamese text (you can use search tools or custom scripts).

2. **Read and Analyze**: 
   - Read the contents of each identified file.
   - Note any special formatting, code blocks, Mermaid diagrams, or GitHub-style alerts (`> [!IMPORTANT]`, `> [!NOTE]`, etc.) that need to be preserved.

3. **Translate Content**: 
   - Translate the Vietnamese text to English.
   - **CRITICAL**: Preserve all Markdown formatting exactly as it is.
   - **CRITICAL**: Do NOT translate code blocks, class names, method names, variable names, or CLI commands.
   - Keep the tone professional and technically accurate, aligning with the project's existing English terminology.

4. **Verify Formatting and Structure**: 
   - Ensure that the resulting translation does not have duplicated text blocks.
   - Check that all links to other documentation files still work and are correctly formatted.

5. **Update Index/References**: 
   - If applicable, update the main index file (e.g., `00-index.md` or `README.md`) to include the translated files with short English summaries.
   - Update any cross-references in other files that might be affected by the changes.

6. **Save Changes**: 
   - Overwrite the original files with the translated English content.
