from importlib.metadata import version
from pathlib import Path

from playwright.sync_api import expect, sync_playwright


def capture(output):
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel="chrome", headless=True)
        try:
            page = browser.new_page(
                viewport={"width": 820, "height": 590},
                device_scale_factor=1,
            )
            page.set_default_timeout(10_000)
            page.goto(
                "https://demo.playwright.dev/todomvc/",
                wait_until="domcontentloaded",
                timeout=25_000,
            )
            entry = page.get_by_role("textbox", name="What needs to be done?")
            for title in ("Review the screenshot diff", "Verify CI", "Write release notes"):
                entry.fill(title)
                entry.press("Enter")
            expect(page.locator(".todo-list li")).to_have_count(3)
            page.locator(".new-todo").blur()
            page.mouse.move(0, 0)
            page.wait_for_function("document.fonts.status === 'loaded'")

            selected_filter = page.locator(".filters a.selected")
            expect(selected_filter).to_have_css("border-top-color", "rgba(175, 47, 47, 0.2)")
            page.screenshot(path=output / "before.png", animations="disabled")

            selected_filter.evaluate(
                "(link) => { link.style.borderColor = 'rgba(175, 47, 47, 0.30)'; }",
            )
            expect(selected_filter).to_have_css("border-top-color", "rgba(175, 47, 47, 0.3)")
            page.screenshot(path=output / "border.png", animations="disabled")
            selected_filter.evaluate("(link) => link.style.removeProperty('border-color')")
            expect(selected_filter).to_have_css("border-top-color", "rgba(175, 47, 47, 0.2)")

            label = page.locator(".todo-list label").filter(has_text="Verify CI")
            expect(label).to_have_text("Verify CI")
            expect(label).to_be_visible()
            label.evaluate("(label) => { label.style.color = 'transparent'; }")
            expect(label).to_have_css("color", "rgba(0, 0, 0, 0)")
            page.screenshot(path=output / "missing-label.png", animations="disabled")
            print(f"Playwright {version('playwright')}, Chrome {browser.version}")
        finally:
            browser.close()


if __name__ == "__main__":
    repo = Path(__file__).resolve().parents[2]
    output = repo / "_build" / "ssim-visual-capture"
    output.mkdir(parents=True, exist_ok=True)
    capture(output)
