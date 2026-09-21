# Bank export target

FMOD Studio exports its built banks here. `core/audio/backends/fmod_backend.gd`
loads every `.bank` in this directory at startup.

The master bank **and** its `.strings` bank are both required - without the
strings bank, event paths cannot be resolved and every lookup fails silently.

## Exporting from FMOD Studio under Proton

The Studio project lives inside a Proton prefix, so it sees the filesystem
through Wine's drive mappings. The prefix maps `Z:` to `/`, which makes this
directory reachable as:

```
Z:\var\home\mackery\pvz-2\audio\banks
```

Set that as the build output in FMOD Studio (Edit > Preferences > Build, or the
platform's build path), so exporting lands the banks straight into the project
rather than somewhere inside the prefix.
