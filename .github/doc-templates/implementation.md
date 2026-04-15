# Implementation Reference

Summarize the overall implementation approach and key considerations for the installer script, based on the API design and installation reference.

## Results

Based on the above research, write a concise summary of the best installation method(s) to implement for devcontainer features and standalone installers, along with any important considerations or trade-offs. The goal is to identify the smallest set of installation methods that cover all possible platforms, use cases, and customization needs, with robust and maintainable implementations.


## Building Blocks

For each building block (function), provide:
- Name: fully qualified name of the function in `lib/` (i.e. `module_name__function_name`).
- Responsibility: a brief description of what this function does and which part of the installation logic it fulfills.
- Reuse or New: indicate whether this building block is reused from `lib/` or if it needs to be newly implemented.
- If New: a detailed specification of the function's behavior, inputs, outputs, and any important implementation details or edge cases to consider.
- If Reused but Extended: a description of how the existing function will be extended or adapted to cover the new use case, including any changes to its behavior, inputs, outputs, or edge case handling.

## Details

Provide a step-by-step plan for implementing the installer script, referencing the building blocks defined above. This plan should clearly indicate how the building blocks will be orchestrated to achieve the overall installation logic, and should cover all non-trivial aspects of the implementation, including handling of edge cases, platform-specific behavior, and any other important considerations.
Add subheadings, bullet points, and formatting as needed to enhance clarity and readability.

## References
Cite any relevant references that will inform the implementation, such as specific sections of the Installation Reference or API Reference documents, official documentation for tools or dependencies, source code of similar implementations, or any other resources that provide important information for the implementation phase.
