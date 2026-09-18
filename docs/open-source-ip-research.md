# Can QuickReminder be open source? — IP research (2026-09-18)

Desk research, **not legal advice**. Two passes: a legal/IP analysis (US + EU/CZ law, Apple's licences) and a precedent survey (what Apple actually enforces on GitHub). Sources at the end.

## Bottom line

**Yes, with low risk**, provided two things are fixed before publishing: remove the iOS reference screenshot from the repository, and never put an SF Symbol or Apple's Reminders icon artwork into the app icon or logo. Everything else (from-scratch Swift code on public frameworks, the word "Reminders" as a label, the name "QuickReminder", MIT licence) sits comfortably inside what thousands of open-source Mac apps already do.

| Area | Risk | Why |
|------|------|-----|
| Copyright in a re-implemented UI look (US) | Low | *Apple v. Microsoft* (9th Cir. 1994): windows, icons, menus, look-and-feel are unprotectable ideas; *Lotus v. Borland*: menu hierarchies are methods of operation. Merger / scènes-à-faire cover "dark panel, title, two fields, icon row, checkmark". |
| Copyright in a GUI (EU / CZ) | Low | CJEU **C-393/09 BSA v. Ministerstvo kultury** (a Czech case): a GUI is not protected as a computer program; it can be a work only if it is the author's own intellectual creation, and layout dictated by function fails that bar. |
| Registered design / design patent on the panel | Low–Medium | GUIs are registrable (Locarno 14-04) and Apple files many. Design right needs no copying, the test is "overall impression". Cheap insurance: don't stay pixel-identical. |
| "Reminders" as the list label | Low | Not on Apple's trademark list (the *icon* is registered, US 4,385,017, the word is not). Referential use for data read through EventKit is exactly what Apple's third-party guidelines allow. |
| "QuickReminder" as project name | Low–Medium | Contains no Apple mark. Apple's iOS feature is reportedly called "Quick Reminder", so rename if it is ever sold or submitted to the App Store; fine for a free GitHub project. |
| SF Symbols via `Image(systemName:)` | Low | Xcode and Apple SDKs Agreement §2.10 licenses system images "solely for the purpose of developing Applications for Apple-branded products" and forbids their use "into app icons, logos or … any other trademark use". In-app use is the licensed use; the app icon must not contain one. |
| Open-sourcing SDK-built code | Low | Only restriction: FOSS terms must not be claimed to cover Apple's SDK, certificates or profiles. Rectangle, IINA, Ice, boring.notch etc. prove the practice. |
| `reference/ios26-quickreminder.png` in the repo | **Medium → fix** | An Apple screenshot is Apple's copyrighted work and contains the registered Reminders icon. Quotation / fair use plausibly apply, but it is the only Apple artefact a takedown bot can match. |
| Private API / reverse engineering | Low | None used. Every documented Apple DMCA action on GitHub targets leaked proprietary material, never clean-room UI clones. |

## What Apple actually enforces on GitHub

Verified by reading notices in `github/dmca` and news coverage: iBoot source leak (2018, forks included), the internal "Atlas" API docs (2021), the leaked apps.apple.com website source (Nov 2025, cascaded to ~8,270 forks via GitHub's fork rule), jailbreak / DRM-adjacent tooling. Zero notices against from-scratch UI recreations.

Precedents that have run for years without any known Apple contact (stars verified live on 2026-09-18):

| Project | Stars | Clones | Licence |
|---------|-------|--------|---------|
| jordanbaird/Ice | ~29.7k | Menu bar manager (Bartender look-alike) | GPL-3.0 |
| FelixKratz/SketchyBar | ~12.4k | Status bar / Control-Center-style widgets | GPL-3.0 |
| TheBoredTeam/boring.notch | ~10.8k | Notch → Dynamic Island panel | GPL-3.0 |
| Ebullioscopic/Atoll | ~4.7k | "Dynamic Island for macOS" | GPL-3.0 |
| DamascenoRafael/reminders-menubar | ~3.9k | Apple Reminders in the menu bar via EventKit | GPL-3.0 |
| Lakr233/NotchDrop | ~2.1k | Notch as AirDrop shelf | MIT |
| jackson-storm/DynamicNotch | ~570 | "completely copies the logic, animations and behavior of a real Dynamic Island" | GPL-3.0 |
| MrKai77/DynamicNotchKit | ~455 | Notch UI library | MIT |
| Celve/Peninsula | ~457 | Notch window switcher | GPL-3.0 |
| orchetect/MacControlCenterUI | ~170 | Control Center menu look-alikes | MIT |

Related disputes were about **trademarks and logos**, not UI: Prepear's pear logo (opposition, settled 2021), 2011 "app store" cease-and-desists. Corellium ran Apple's actual iOS binaries and still won on fair use. Apple does hold a US trademark on **"Dynamic Island"** (serial 97585886), so do not use that phrase as a product name; descriptive use in a README is what every notch project does today.

Community norm: MIT or GPL-3.0; explicit "not affiliated with Apple" disclaimers are the exception, not the rule, but they are cheap good-faith signalling.

## Recommended actions before making the repo public

1. **Remove `reference/ios26-quickreminder.png`** from the repo and from git history (`git filter-repo` or a fresh repo), and gitignore `reference/`. Describe the design in words (SPEC §4 already carries the measured metrics).
2. **App icon**: draw an original icon. No SF Symbol, no Apple Reminders artwork (registered trademark) in the icon or any logo.
3. **Licence**: MIT (or Apache-2.0 for the explicit patent grant). Avoid GPL only to sidestep any argument about FOSS terms reaching Apple-issued certificates or profiles.
4. **README disclaimer** near the top:
   > Not affiliated with, endorsed by or sponsored by Apple Inc. Apple, macOS, iOS, Xcode, SF Symbols and Reminders are trademarks of Apple Inc., registered in the U.S. and other countries. QuickReminder is an independent, from-scratch implementation that uses only public Apple frameworks, contains no Apple source code or assets and uses no private APIs. It reads and writes the user's reminders through the public EventKit framework.
5. **Wording**: "inspired by the iOS quick-reminder overlay", "works with Apple Reminders". Never phrase it as an Apple product or "the iOS Quick Reminder for Mac". Keep "Reminders" visually subordinate to the project name.
6. **Slight de-tuning of 1:1 fidelity** (own accent, spacing or corner radius) if a registered-design claim ever worries you; optional for a hobby repo.
7. **Rename** (NotchNote, JotDown, NotchCapture…) only if the app is ever sold or submitted to the App Store.
8. Add a short `TRADEMARKS.md` / `NOTICE` restating item 4.

## Sources

- Apple v. Microsoft, 35 F.3d 1435 (9th Cir. 1994) — https://law.justia.com/cases/federal/appellate-courts/F3/35/1435/605245/
- Lotus v. Borland, 49 F.3d 807 (1st Cir. 1995) — https://www.bitlaw.com/source/cases/copyright/Lotus.html
- CJEU C-393/09 BSA v. Ministerstvo kultury — https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=celex%3A62009CJ0393
- Apple, Guidelines for Using Apple Trademarks and Copyrights — https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html
- Apple trademark list — https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html
- Xcode and Apple SDKs Agreement, §2.10 System-Provided Images — https://www.apple.com/legal/sla/docs/xcode.pdf
- Reminders icon registration (US 4,385,017) — https://www.patentlyapple.com/patently-apple/2013/08/apples-reminders-icon-is-now-a-registered-trademark.html
- GUI protection as Registered Community Design — https://cms.law/en/int/expert-guides/protection-of-graphical-user-interfaces-as-registered-design/eu
- Apple v. Samsung design patents — https://www.mintz.com/insights-center/viewpoints/2018-05-31-smartphone-wars-last-jury-samsung-owes-539m-infringing-apples
- Apple DMCA notices: iBoot 2018 — https://github.com/github/dmca/blob/master/2018/2018-02-08-Apple.md ; Atlas docs 2021 — https://github.com/github/dmca/blob/master/2021/10/2021-10-18-apple.md ; apps.apple.com 2025 — https://github.com/github/dmca/blob/master/2025/11/2025-11-05-apple.md
- Prepear settlement — https://www.macrumors.com/2021/02/09/prepear-settles-apple-trademark-dispute/
- "Dynamic Island" trademark, serial 97585886 (USPTO / Justia)
