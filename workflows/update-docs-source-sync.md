---
description: Update documentation to match source code changes
---

This workflow is used when the content of documentation files needs to be updated to match the actual implementation in the source code.

## Workflow Steps:

1. **Receive Input Files**: 
   - Receive the list of input documentation files from the user that need to be updated.

2. **Map Documents to Source Code**: 
   - For each input document file, identify the corresponding source code files that are mentioned or documented within it.
   - You can use search tools like `grep_search` or examine the document's content to find class names, function names, or file paths.

3. **Read and Analyze Content**: 
   - Use the `view_file` tool to read the full content of the documentation file.
   - Use the `view_file` tool to read the relevant parts of the mapped source code files.

4. **Compare and Update**: 
   - Compare the documentation's descriptions, code snippets, and APIs against the actual source code implementation.
   - If there are discrepancies (e.g., changed method signatures, new parameters, removed features), update the documentation content to reflect the current state of the source code.
   - Ensure you maintain the existing Markdown formatting and structure of the document.

5. **Save Changes**: 
   - Use the `replace_file_content` or `write_to_file` tools to save the updated documentation content.

6. **List Changed Files**: 
   - After completing the updates, provide a summary list to the user of all the documentation files that were changed, along with a brief description of the updates made.
