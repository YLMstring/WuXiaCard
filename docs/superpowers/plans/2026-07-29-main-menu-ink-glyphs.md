# Main Menu Ink Glyphs Implementation Plan

1. Extend `tests/test_main_menu.gd` to require four matching image glyphs,
   empty visible text, preserved button behavior, and a notice below the grid.
2. Preload the four PNGs in `scripts/main_menu_controller.gd`.
3. Create non-interactive, aspect-preserving `TextureRect` children at runtime
   for the title and three existing buttons.
4. Keep the existing button hit areas and pressed-scale feedback.
5. Position the notice at approximately 83 percent of the square artwork
   height.
6. Run script checks, the focused menu and flow suites, then inspect portrait
   and wide runtime frames.
