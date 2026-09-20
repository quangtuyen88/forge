# Today — Option 2, corrected prompt

Paste this whole block into Stitch as a **new screen**, not as an edit of an existing one.
Editing or "revising" an existing screen makes the model copy the old layout instead of
following the spec.

---

Create a brand new screen titled "Today — Plain Language". Ignore every other screen in this project; do not copy their layout or their wording. Build only what is written here, in this order.

FIXED BOTTOM BAR, build this first and make it position:fixed at the bottom of the viewport above the tab bar, with a blurred dark backdrop. Inside it one lime #ccff00 pill button, 58px tall, full width minus 16px margins, black Barlow Condensed bold text reading "Start Full C · ≈60 min" with a small play icon. The page content scrolls underneath this bar. This bar is visible at every scroll position including the very top of the page.

Then the scrolling content:

Header, position fixed at top, blurred: the word "Today" in 30px Barlow Condensed bold, sentence case. On the right two 56px circle buttons, a coach avatar and a settings gear.

Line 1: "Week 2 of 6 · Friday, Sep 18" in 13px Inter, colour #94a3b8. Nothing else on this line.

Line 2: "Good morning, Alex" in 26px Barlow Condensed bold, sentence case.

Card 1, #151518, 24px radius, 1px #27272e border:
Row: "Full C" in 30px Barlow Condensed bold sentence case, and on the right a grey pill "≈60 min".
One lime-tinted pill underneath: "Hypertrophy · Week 2".
Then a single circle progress ring, exactly one ring, 150px across, 12px stroke, lime #ccff00 filled to 84 percent over a #27272e track. Centred inside the ring the number 84 in 54px Barlow Condensed extrabold white, and under it the word READY in 11px lime.
Under the ring, two text stats side by side split by a thin vertical line. Left: "Sessions" in 11px #94a3b8 above "3/3" in 26px white. Right: "Sets" in 11px #94a3b8 above "4/72" in 26px white. No coloured dots, no extra rings.
Last row of the card, 56px tall: a small coach avatar, "Ready for peak load · 3 tweaks applied" in 15px Inter white, chevron on the right.

Card 2: seven columns labelled S M T W T F S, each column 44px wide and 56px tall. Under S an empty grey outline circle. Under M and W a lime filled circle with a black tick. Under T a grey outline circle with a moon. Under the second T a lime filled circle with a black tick. Under F a lime filled circle with a black lightning bolt and a small lime dot below it. Under the last S an empty grey outline circle.

Card 3 and Card 4, side by side, equal width, 96px tall. Left card: "Streak" in 11px #94a3b8, then "1" in 30px white with "wk" in #94a3b8 beside it, small flame icon top right. Right card: "This week" in 11px #94a3b8, then "2,609" in 30px purple with "kg" in #94a3b8 beside it. Each card contains exactly those three pieces of text and nothing more.

Card 5: heading "Today's muscles" in 16px Barlow Condensed bold, sentence case, alone on its row with no text to its right. Inside, two human body silhouettes side by side in dark grey, front and back, with the thighs glowing bright lime, the upper chest and calves glowing dimmer lime. Small labels "Front" and "Back" beneath them in 11px #94a3b8. Then one row of three items split by thin vertical lines: "Primary" over "Quads", "Secondary" over "Pecs", "Fatigue" over "Low". Labels 11px #94a3b8, values 16px white.

Card 6: heading row with "Today's workout" in 16px Barlow Condensed bold sentence case on the left and a grey pill "4 exercises" on the right. Under it one panel containing four rows stacked vertically, each 64px tall, separated by hairlines. Each row has the exercise name in 17px Inter white on the left with a 13px #94a3b8 line beneath it, and a chevron on the right. The four rows in order:
Bulgarian Split Squat / 4 sets · 25 kg
Incline Dumbbell Press / 3 sets · 40 kg
Barbell Row / 3 sets · 44 kg
Face Pull / 3 sets · 20 kg
No pictures anywhere on this screen. No play buttons on these rows.

Leave 120px of empty space at the end of the scrolling content so the last card clears the fixed bottom bar.

Tab bar at the very bottom, four items, icon above label, labels in sentence case: Today with a flame and lime highlight, Coach with a chat bubble, Progress with a bar chart, Crew with two people.

Write every heading, button and tab label in sentence case. The only text in capitals on this screen is the single word READY inside the ring. Background #0d0d0f, cards #151518, borders #27272e, body text white, secondary text #94a3b8. Lime #ccff00 appears only on the ring, the completed and today markers, the muscle highlights and the bottom button. Purple appears only on 2,609.

---

## Check the result against these seven things

The first generation failed every one of them, so verify before accepting a screen.

1. The lime **Start Full C** button is visible without scrolling, at the top of the page.
2. Exactly **one** ring, not three.
3. **84** is the largest thing on the screen, roughly twice the height of any other number.
4. The words **Recovery Index**, **Meso Sets**, **Active Mesocycle**, **Biomechanics HUD**, **Target Activation**, **Live Telemetry** and **PR Day** appear nowhere.
5. No **+12% vs last week** and no **4 of 4 targets hit** — those figures cannot be computed yet.
6. Everything is sentence case except the single word READY.
7. No photographs and no play buttons.
