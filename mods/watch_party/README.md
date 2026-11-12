# Watch Party

A mod for Home: Equestria, by HorseBucker. Needs game version 0.3.1 or newer.

Watch TV and browse the web! Invite a pony over and she sits down and watches with you.
Find the TVs for free in the Everfree, or wait for somepony else to find them and put them up for
sale in the market.

Three televisions from your world: a vintage console set and a 65-inch flatscreen (on a stand, or
wall-mounted). They play videos from your own folders, YouTube and other web pages, and photo
slideshows. Ponies you invite watch along and talk about what's on. Works on desktop and in VR.

## Install

Watch Party is one file plus two free downloads. Put all three in the game folder, the one with
`HomeEquestria.exe` in it.

1. **The mod.** Put `watch_party.pck` in the `mods` folder inside the game folder (in the game:
   Settings → Mods → Open mods folder). Start the game. Settings → Mods should list Watch Party
   under "Your mods". The game also comes with an older Watch Party of its own, off by default:
   the newer of the two is used, and the other is listed as superseded.
2. **ffmpeg, for videos.** On https://www.gyan.dev/ffmpeg/builds/ under "release builds", download
   `ffmpeg-release-essentials.zip`. Unzip it and put the whole folder it makes
   (`ffmpeg-<version>-essentials_build`) in the game folder. Don't rename it.
3. **gdCEF, for the web browser (optional).** On
   https://github.com/Lecrapouille/gdcef/releases/tag/v0.20.0-godot4 download
   `gdcef-0.20.0_godot-4.5.zip` (about 1 GB). It has to be this version: newer ones won't load in
   the game. Unzip it and put its `cef_artifacts` folder in the game folder.

The game folder then looks like this:

```
HomeEquestria.exe
mods\watch_party.pck
ffmpeg-<version>-essentials_build\bin\ffmpeg.exe   (and ffprobe.exe)
cef_artifacts\...                                   (only for the browser)
```

To check it all worked, open Settings → Watch Party → Setup (or the TV menu's Setup tab). It shows
whether ffmpeg and gdCEF are found and has buttons for the download pages and the game folder.
Nothing outside the game is started until then: ffmpeg is looked for the first time you use a TV
or open that page.

## Uninstall

Switch the mod off in Settings → Mods, or delete `watch_party.pck` from the mods folder. Your
saves stay fine: the game sets your TVs and remotes aside and gives them back, where they were,
when the mod is on again.

The mod's settings, browser logins and vision API keys are in
`%APPDATA%\home-equestria-public\mods\data\watch_party\`. Delete that folder too if you want them
gone.

## Getting the TVs

- For your first few days in a world, the TVs lie somewhere in the Everfree, free to whoever finds
  them. Wait too long and somepony else finds them and sells them in Ponyville.
- There's one of each kind. Once you have one, the forest and the market have no other.
- Lost one? If a TV you had is gone for any reason, another one is for sale at the market from 6
  the next morning, at the usual price.
- The remote comes with your first TV. The market sells spares.
- A TV does nothing at first. How to get it working is for you to find out.
- Rather skip that quest? Turn on **Ozone-powered TVs** in Settings → Watch Party. Every TV works
  as soon as you set it down. Why? Because Equestria's air is thick with ozone, that's why.
- Stuck? Settings → Watch Party → SPOILER: Where are the TVs? → Show.

<details>
<summary>Spoilers: where the TVs are, and how to get them working</summary>

- **In the forest.** The vintage set is at the forest's edge, not far from Fluttershy's cottage.
  The two flatscreens are much deeper in, on the way to Zecora's hut.
- **Rumours.** Fluttershy heard something heavy crash down near her cottage one night. Zecora has
  seen a strange black slab on a little table and can lead you to it. The wall flatscreen has no
  rumour.
- **At the market.** The vintage set (and a remote) go on sale from your second day, both
  flatscreens from your third, in one of the market tents. Vintage set 40 bits, each flatscreen
  150, remote 10.
- **Waking them.** Somepony who knows magic has to give a TV power of its own: **Twilight**,
  **Princess Celestia** or **Princess Luna** (only while they visit you), or **Trixie**. Bring the
  TV to her, or set it down near her, and she takes it from there. Each does it her own way.

</details>

## Using a TV

- **Placing.** Place it like furniture (desktop: Shift+Q, the wheel turns it; VR: let go of the
  grip over the floor or a table), indoors or outdoors. The wall flatscreen hangs on walls, fences,
  rocks and tree trunks. To pick it up again, press E on its top or side.
- **The remote** works the nearest TV that's on.
  - Desktop: click to play or pause, hold the click to switch the TV off or on, right click for the
    TV menu. Wheel skips 10 seconds, Left/Right change the video, Up/Down change the volume. A card
    in the bottom right corner lists these.
  - VR: the trigger plays or pauses, hold it to switch the TV off or on, pull it twice quickly for
    the TV menu.
- **Zoom (desktop).** Press Home to bring the view right up to the screen you're facing, so you can
  watch from across the room. Home or Esc steps back. In VR, just lean in.
- **The TV menu** has what's on, the video library and folders, sound and subtitle tracks, the
  picture (Fit or Fill, the CRT look on the vintage set), the slideshow and browser, and Pony
  vision.
- Each video resumes where you left off.

## Watching with ponies

- Once you have a TV set up in a house, ask any pony if she wants to watch something with you.
  She decides for herself. If she says yes, she goes to the TV (or walks along with you until you
  reach one) and sits on a couch or lies down in front of it.
- While she watches, she remarks on what's on now and then. Set how often in the TV menu or
  Settings → Watch Party (Chatty, Normal, Relaxed, Quiet or Silent).
- She follows a film through its **subtitles**, even if they're switched off on screen (see
  Subtitles below). Without any she only knows the title.
- She only knows what she actually watched with you, so no spoilers.
- She gets up when the watching is over, when you leave, or when the TV stays off.

## Subtitles

Subtitle tracks inside the video, and `.srt`, `.ass`, `.ssa` or `.vtt` files in the same folder
named like the video (`Movie.mkv` and `Movie.srt`, or `Movie.en.srt`). Free subtitle files:
OpenSubtitles.com or Podnapisi.net. Pick one made for your copy so the timing matches.

**No subtitle file? Ponies can still follow.** Blu-ray and DVD subtitles are pictures, not text, so
the mod reads them with OCR in the background, a little ahead of where you are. Each video is only
read once: the result is kept for next time. The TV menu's "They follow" line shows how far it
has got. A video with no subtitle track at all has its picture checked every 2 seconds for
subtitles burned into it (less accurate). Both can be switched off in Settings → Watch Party.

- **Windows:** uses Windows' own OCR, through the PowerShell that comes with Windows. Nothing to
  install.
- **Linux:** install Tesseract with your package manager (`tesseract-ocr`, with its English data).

## Pony vision (optional)

With Pony vision on, ponies watching with you now and then see the actual picture, not just the
subtitles. Ask "look at this" or "who's that?" and she looks before she answers.

It needs a vision AI service of your own: Google Gemini, Anthropic Claude, any OpenAI-compatible
server, or the game's own dialogue settings. Set it up in TV menu → Pony vision. You can list
several and set a daily limit of calls for each. Pictures of the screen are sent to the service
you choose. API keys are saved in plain text in the mod's settings file.

## Web browser (needs gdCEF)

- Open it from TV menu → Photos & web.
- **Desktop:** click the screen for TV mode. The mouse and keyboard then work the page, and Esc
  gives you back the game.
- **VR:** point a hand at the screen for a laser. The trigger clicks, the stick scrolls, and B/Y
  shows a keyboard.
- Tabs, back and forward, zoom, and right-click menus all work. Downloads go to your Downloads
  folder.
- What ponies know about what you browse is up to you: Settings → Watch Party → Ponies know of the
  browser (Nothing, Page & words, or Also pictures). With Nothing, nothing about it leaves your
  computer.
- Ads are blocked using EasyList's ad server list (https://easylist.to, CC BY-SA 3.0). YouTube's
  own ads still play.
- Netflix and other paid streaming services, and Twitch and Kick, can't play.
- To stop a crash in gdCEF 0.20's Chromium, the mod changes two bytes in
  `cef_artifacts/windows/libcef.dll` and keeps the original as `libcef.dll.original`.

## Photo slideshow

TV menu → Photos & web: pick a folder and how long each picture shows. GIFs and WebMs play too.
Turn on "Slideshow on a set left off" and a TV you leave off starts the slideshow by itself, like
a picture frame.

## Troubleshooting

- **Low frame rate.** Settings → Watch Party → Light from the screen: Near or Off. For the browser,
  15 frames a second or 75% page resolution.
- **Smearing or ghosting on the screen.** The game's upscaling causes it. In Settings
  → Graphics, set Render scale to 100%.
- **Bug reports.** Turn on the game's debug mode (press Settings → Updates five times), then send
  `%APPDATA%\home-equestria-public\logs\godot.log`.
