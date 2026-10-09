# Product Hunt launch: ThoughtCop

## Name
ThoughtCop

## Tagline (max 60 characters)
Catch your AI coding agent breaking your rules as it thinks

## Links
- Website: https://github.com/deepmtch/thoughtcop
- Story: https://airabbit.blog/thoughtcop-reads-your-agents-thoughts/

## Topics
Developer Tools, Artificial Intelligence, Open Source, Mac

## Pricing
Free (open source, GPL-3.0)

## Description
A free, open-source macOS menu-bar app that reads what Claude Code and Codex are thinking while they work. Write any rule in plain English: skipping tests, touching secrets, working around a blocker, claiming done without proof. ThoughtCop checks every thought and reply against your rules and flashes a red bolt the moment one is broken. No hook, no proxy, nothing changes in the agent.

## Gallery (1270×760, in this order)
1. gallery/1-cover.png
2. gallery/6-run.gif
3. gallery/3-caught-thought.png
4. gallery/2-how-it-works.png
5. gallery/4-menubar-hover.png
6. gallery/5-your-rules.png

## Thumbnail
thumbnail-240.png

## First comment

AI coding agents quietly break the rules you give them.

They skip tests, touch files they shouldn't, claim "done" without proof, or hit a wall and work around it instead of asking. You find out at the end, from a tidy summary.

The decision is visible much earlier, in the agent's own reasoning. In a real run, Claude Code thought: "Running the test suite likely won't work … worth flagging, but let me make the edit first." ThoughtCop flagged that thought about a second after it was written.

How ThoughtCop works:
• Claude Code and Codex write their thoughts to session files on your Mac
• ThoughtCop reads them live. No hook, no proxy, nothing changes in the agent
• A fast model (Groq or Cerebras) checks each thought against your rules
• On a match, the brain in your menu bar gets a red bolt and shows the exact quote

The rules are yours. Any rule you can say in a sentence, checked word for word. For example:
• "The AI is taking a shortcut or workaround without asking the user"
• "The AI says something is done without showing the output that proves it"
• "The AI reads, prints or copies an API key"
• "The AI changes files outside the folder it was asked to work in"

A full session of checks costs under two cents. Free and open source.

Which rules would you add? 👇

## Notes before launch
- There is no notarized download yet; people build from source. Product Hunt visitors expect a download, so a signed release (`./Scripts/release.sh`, needs a Developer ID) would help a lot.
- The deepmtch repo must be pushed before launch day; the link points there.
