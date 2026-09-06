# Mantra Moment website

Build from the repository root with:

```sh
hugo --source website --gc --minify
```

Hugo writes to `website/public/`, which is gitignored. Netlify builds and publishes the site using the root `netlify.toml`.

## App icon

The website uses `static/images/app-icon.png` for its app image and favicon. Export it from the app's Icon Composer source with the executable bundled inside Icon Composer (the system `/usr/bin/ictool` is a different tool):

```sh
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  "Mantra Moment/AppIcon.icon" \
  --export-image \
  --output-file website/static/images/app-icon.png \
  --platform macOS --rendition Default \
  --width 512 --height 512 --scale 1
```

Run the command from the repository root whenever the app icon changes, then rebuild the site.
