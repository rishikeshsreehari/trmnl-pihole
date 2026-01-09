import os
import re

class Chef:
    MAX_TITLE_LENGTH = 50
    MAX_INLINE_STYLES = 6

    def __init__(self, root_dir):
        self.root_dir = root_dir
        self.suggestions = []
        # Key: filename, Value: content
        self.markup_files = {}

    def load_files(self):
        """Recursively find all .liquid files in subdirectories."""
        for root, _, files in os.walk(self.root_dir):
            for file in files:
                if file.endswith('.liquid'):
                    path = os.path.join(root, file)
                    try:
                        with open(path, 'r', encoding='utf-8') as f:
                            self.markup_files[path] = f.read()
                    except Exception as e:
                        print(f"Error reading {path}: {e}")

    def critique(self):
        if not self.markup_files:
            return "No .liquid files found."

        all_content = " ".join(self.markup_files.values())

        # 1. Async check
        if 'async function' in all_content.lower():
            self.suggestions.append("Async JavaScript functions are not allowed.")

        # 2. Highcharts checks
        if 'highcharts' in all_content.lower():
            if not re.search(r'animation:\s{0,6}false', all_content):
                self.suggestions.append("Highcharts should have animations disabled.")
            if 'append_random' not in all_content:
                self.suggestions.append("Use 'append_random' filter for Highcharts elements.")

        # 3. Inline Styles check (Regex approach)
        styles = ['display', 'justify-content', 'padding', 'margin', 'background-color', 
                  'color', 'border-radius', 'text-align', 'object-fit', 'font-size']
        style_count = sum(len(re.findall(re.escape(s), all_content)) for s in styles)
        if style_count > self.MAX_INLINE_STYLES:
            self.suggestions.append(f"Too many inline styles ({style_count}). Use Framework classes.")

        # 4. TRMNL Layout Class check
        layout_pattern = r'\b(view(--|__)(full|half_horizontal|half_vertical|quadrant))\b["\']>'
        if re.search(layout_pattern, all_content):
            self.suggestions.append("Remove manual 'view--full/half' classes; they are applied automatically.")

        # 5. DOM Load check
        if any(x in all_content.lower() for x in ['window.onload', 'window.addeventlistener("load")', "window.addeventlistener('load')"]):
            self.suggestions.append("Listen for 'DOMContentLoaded' instead of 'window.onload'.")

        # 6. Static Image Link check (Using Regex instead of BeautifulSoup)
        # Finds <img src="..."> where src doesn't contain Liquid tags {{ }}
        img_src_pattern = r'<img [^>]*src=["\'](?!.*{{)([^"\']+)["\']'
        found_images = re.findall(img_src_pattern, all_content)
        if found_images:
            # Note: We aren't pinging the URLs here to keep it a pure "offline" linter,
            # but we identify them for manual review.
            self.suggestions.append(f"Found {len(found_images)} static image links. Ensure they respond with 200 OK.")

        # 7. Empty content check
        for path, content in self.markup_files.items():
            if len(content.strip()) < 10:
                self.suggestions.append(f"Layout file '{os.path.basename(path)}' seems empty.")

    def output_results(self):
        print(f"--- TRMNL Chef Report ---")
        if not self.suggestions:
            print("✅ Perfect! No improvements suggested.")
        else:
            for s in set(self.suggestions):
                print(f"⚠️  {s}")

if __name__ == "__main__":
    chef = Chef('.') # Starts in current directory
    chef.load_files()
    chef.critique()
    chef.output_results()