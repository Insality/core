# Druid Widget Store

In this Druid Widget Store you can find all the widgets that are available and install them with one click to your project. This is will be your local copy of the widget, so you can change it easily!


## Open Druid Widget Store

Select `Edit` -> `[Druid] Widget Store` in the menu. Ensure the Druid library is installed and fetched.


## Contributing Your Widget

Want to share your widget with the community? Follow these steps to add your widget to the store via Pull Request:

### Step 1: Prepare Your Widget Files

Create a directory structure for your widget:

```
widget/
└── {YourAuthorName}/
    └── {widget_id}/
        ├── {widget_id}.json      # Widget manifest (required)
        ├── {widget_id}.lua       # Widget script
        ├── {widget_id}.gui       # GUI file (if needed)
        ├── {widget_id}.md        # API documentation (recommended)
        ├── {widget_id}.png       # Preview image (recommended)
        └── example/              # Example project (optional)
            ├── example_{widget_id}.collection
            ├── example_{widget_id}.gui
            └── example_{widget_id}.gui_script
```

**Important**: The folder name must match the widget ID in the manifest JSON file.

### Step 2: Create Widget Manifest

Create a `{widget_id}.json` file with the following structure:

#### Required Fields

- `author` (string): Your GitHub username or author name
- `version` (number): Version number (start with 1)
- `id` (string): Unique widget identifier (usually matches folder name)

#### Recommended Fields

- `title` (string): Display name for your widget
- `description` (string): Brief description of what the widget does
- `content` (array): List of files to include in the widget package
  ```json
  "content": [
    "widget_id.lua",
    "widget_id.gui"
  ]
  ```
- `api` (string): Path to API documentation file (e.g., `"widget_id.md"`)
- `image` (string): Path to preview image (e.g., `"widget_id.png"`)
- `tags` (array): Tags for categorization (e.g., `["debug", "ui", "system"]`)
- `author_url` (string): Your GitHub profile or website URL

#### Optional Fields

- `depends` (array): Dependencies on other widgets in format `["Author:widget_id@version"]`
  ```json
  "depends": ["Insality:mini_graph@1"]
  ```
- `example` (string): Path to example collection (e.g., `"/widget/Author/widget_id/example/example_widget.collectionc"`)
- `example_url` (string): External URL to example (takes priority over `example` field)

### Step 3: Example Manifest

Here's a complete example of a widget manifest:

```json
{
  "author": "YourAuthorName",
  "id": "my_awesome_widget",
  "version": 1,
  "title": "My Awesome Widget",
  "description": "A widget that does something amazing",
  "image": "my_awesome_widget.png",
  "api": "my_awesome_widget.md",
  "author_url": "https://github.com/YourAuthorName",
  "tags": ["ui", "custom"],
  "content": [
    "my_awesome_widget.lua",
    "my_awesome_widget.gui"
  ],
  "depends": []
}
```

### Step 4: Create Pull Request

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YourUsername/core.git
   cd core
   ```
3. **Create a new branch**:
   ```bash
   git checkout -b add-my-widget
   ```
4. **Add your widget files** to `widget/{YourAuthorName}/{widget_id}/`
5. **Commit your changes**:
   ```bash
   git add widget/YourAuthorName/my_awesome_widget/
   git commit -m "Add my_awesome_widget widget"
   ```
6. **Push to your fork**:
   ```bash
   git push origin add-my-widget
   ```
7. **Create a Pull Request** on GitHub:
   - Go to the original repository
   - Click "New Pull Request"
   - Select your fork and branch
   - Fill in the PR description
   - Submit the PR

### Step 5: PR Review

After submitting your PR:
- The automated build system will validate your widget
- Maintainers will review your code and manifest
- If changes are needed, update your branch and push again
- Once approved, your widget will be automatically published to the store!

### Tips for Success

- **Test your widget** before submitting - make sure it works in a clean project
- **Write clear documentation** - include usage examples in your `.md` file
- **Add a preview image** - helps users understand what your widget does
- **Use descriptive tags** - makes your widget easier to find
- **Follow existing code style** - check other widgets for reference
- **Start with version 1** - increment when you make updates

### Updating Your Widget

To update an existing widget:
1. Increment the `version` number in the manifest
2. Make your changes
3. Create a new PR with the updated version
4. The system will preserve all previous versions automatically

### Questions?

If you have questions or need help, feel free to:
- Open an issue on GitHub
- Check existing widgets for examples

