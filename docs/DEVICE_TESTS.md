# Device tests

Nothing in this file can be checked by the test suite. Each item is here
because it either failed on a phone once, or has never been run on one at all.

In the order it should be run, in sittings that stand alone. **★** marks the
nine where a failure either makes the app useless, silently eats data, or has
shipped broken before — do those first if time is short.

The user works through this and reports back by number. There is a tickable
version of the same list published as an artifact; this file is the copy that
survives in the repository.


## Before anything else

**01. ★ Installing over the old version keeps your data**  
Do: Install this APK over whatever was already on the phone.  
Expect: Every brew survives, with its score, rating and rubric.  

**02. ★ The release build can reach the network**  
Do: On this release APK, log a brew in free text and let it parse and score.  
Expect: It parses. If it always says "no connection" while your wifi is fine, the <code>INTERNET</code> permission is missing again.  


## Log a brew the new way

**03. ★ The app works fully signed out**  
Do: Without signing in: log a brew, score it, edit it, delete it, restore it.  
Expect: All of it works. Nothing nags you to sign in.  
Why: Signing in is optional and must stay optional. SQLite is the source of truth; Firestore is only a mirror.

**04. ★ "Yesterday at 11.30" lands on yesterday**  
Do: New brew: "i brewed espresso yesterday at 11.30 am, 18g in 36g out".  
Expect: Brewed at reads yesterday, 11:30, tagged "from what you typed".  
Why: Verified against the live Worker, not on a phone. The phone sends its own clock, so this is where a timezone mistake would show.

**05. You can correct the time by hand**  
Do: Tap Brewed at, pick a date and a time. Try picking a future date.  
Expect: It changes. Future dates aren't offered at all.  

**06. The basket fields read correctly**  
Do: Open an espresso form and look at the Brew section.  
Expect: Basket capacity in grams, Basket diameter as 51/53/54/58 mm, Basket type as two options — no free-text box.  

**07. Pressurised explains itself**  
Do: Set Basket type to Pressurised.  
Expect: A note appears saying WDT and distribution have little to do there, and that it isn't scored against you.  

**08. Same shot scores differently by basket**  
Do: Log an espresso with WDT and distribution off, tamp on, basket pressurised. Then the same again as non-pressurised.  
Expect: The pressurised one scores clearly higher. On the Worker directly it was 100 against 86.  


## Edit one and watch the score

**09. Editing announces the new score**  
Do: Edit a scored brew's dose or yield and save.  
Expect: A dialog: old number struck through, arrow, new number, and the reasons.  

**10. An old brew warns you the rules moved**  
Do: Edit a brew that was scored before today, and save.  
Expect: The dialog adds a line saying the scoring rules also changed, so part of the difference isn't your edit.  
Why: Old entries are r2, new ones r3. On a pressurised basket that difference alone is worth about fourteen points.

**11. Changing only the time doesn't re-score**  
Do: Edit a brew, change only Brewed at, save.  
Expect: Save is enabled, the time changes, the score doesn't move and no scoring spinner appears.  

**12. Save stays dead when nothing changed**  
Do: Open an edit screen and change nothing.  
Expect: The button is disabled and reads "Nothing changed".  


## Find things again

**13. Search finds by name and by your own words**  
Do: Search <code>tubruk</code>. Then search a word you typed in a brew's description but that no field stores.  
Expect: Both find the right brews.  

**14. The filter survives opening a brew**  
Do: Filter by a method, tap into a brew, come back.  
Expect: Still filtered, count still shown.  

**15. The full log scrolls properly**  
Do: Open the full log with a good number of entries and scroll to the bottom and back.  
Expect: Smooth, and it doesn't jump to a strange position when you return to it.  
Why: An expanding tile once stored a boolean where the list kept its scroll offset, and the list read it as a position.


## Look and language

**16. Guide photos, uncropped**  
Do: Open several guides — espresso, siphon, cold brew, kopi saring, AeroPress.  
Expect: A photo on each, whole and not cut off, with the photographer and licence beneath it. Kopi talua has none — that's expected.  

**17. The score screen shows the same photo**  
Do: Log a brew and reach the score reveal.  
Expect: The method's photo sits above the reasons, credited.  

**18. Photo credits are reachable in Settings**  
Do: Settings → Photo credits.  
Expect: Fifteen photos listed with author, licence and source.  
Why: Naming the photographer is a licence condition, not a courtesy. If this screen is missing or empty, the app is in breach.

**19. ★ Indonesian everywhere**  
Do: Switch to Bahasa Indonesia and walk every screen — guides, full log, settings, the new dialogs, the dropdown values.  
Expect: No English left except method and category names, which stay English on purpose.  
Why: This has broken twice: labels froze in English, and dropdowns showed raw ids like <code>kalitaWave</code> for weeks.


## Set the reminder, then carry on

**20. ★ It fires when you haven't brewed**  
Do: On a day with no brew logged, set the reminder a few minutes ahead and lock the phone.  
Expect: The notification arrives.  
Why: Scheduling is inexact, so it can land a little late. Late is fine; never is the failure.

**21. It stays quiet when you have**  
Do: Log a brew, then set the reminder a few minutes ahead.  
Expect: Nothing arrives. It only nags on days you've logged nothing.  

**22. Changing the time takes effect**  
Do: Change the reminder time in Settings, close the app, reopen it.  
Expect: The new time is still shown, and it's the one that fires.  

**23. Notifications turned off is handled**  
Do: Turn off notifications for Kopi Kompas in Android settings, then open Settings in the app.  
Expect: It tells you notifications are off rather than pretending the reminder is on.  


## Signing in

**24. ★ Google sign-in**  
Do: Settings → Sign in → Continue with Google.  
Expect: Account picker appears, you come back signed in, Settings shows your account.  
Why: Needs the release SHA-1 registered in Firebase. If it fails silently on the release APK but works in debug, that's the signing fingerprint.

**25. Create an account with email**  
Do: Sign in → Use email → No account yet? → create one.  
Expect: Signed in immediately after creating.  

**26. Sign in again with that email**  
Do: Sign out, then sign back in with the same email and password.  
Expect: Signed in, and your log is still there.  

**27. Wrong password says the right thing**  
Do: Sign in with a deliberately wrong password.  
Expect: "Wrong email or password" / "Email atau sandi salah" — not a raw Firebase error code.  

**28. Password reset email arrives**  
Do: Tap Forgot password.  
Expect: Confirmation on screen, and the email actually lands in your inbox.  

**29. Phone number and SMS code**  
Do: Sign in → Use phone number → your number → enter the 6-digit code.  
Expect: SMS arrives, code is accepted, you're signed in.  
Why: The one with a real cost attached — Firebase bills SMS. Worth knowing whether it works before you rely on it.

**30. Signing out doesn't take your log with it**  
Do: Sign out.  
Expect: Every brew is still on the phone. Settings goes back to "not signed in".  


## Backing up

**31. ★ Back up now, and the count is right**  
Do: Settings → Back up now.  
Expect: "Backed up N brews", where N is how many you actually have.  

**32. Restoring twice doesn't duplicate anything**  
Do: Restore from backup. Then restore again.  
Expect: Same number of brews both times. No duplicates in the log.  
Why: Push is keyed on each entry's uuid so it should be idempotent. This is where that either holds or doesn't.

**33. ★ A deleted brew stays deleted**  
Do: Delete a brew, back up, then restore.  
Expect: It does <strong>not</strong> come back to the main log. It's still sitting in Settings → Deleted entries.  
Why: Deleted rows are mirrored <em>as deleted</em> on purpose. If they were simply absent, a restore would resurrect everything you'd thrown away.

**34. A newer local edit survives a restore**  
Do: Back up. Edit a brew's dose. Restore from backup.  
Expect: Your newer dose wins. The restore doesn't overwrite it with the older one.  

**35. No connection still saves the brew**  
Do: Turn on aeroplane mode. Log a brew and fill it in by hand.  
Expect: It saves. It may not score, and it won't back up, but the brew is kept.  
Why: A backup failure must never surface as a save failure.


## The one that wipes the phone — do this last

**36. The real test: reinstall and get it back**  
Do: Back up. Uninstall the app. Reinstall, sign in, restore.  
Expect: Your whole log returns, scores and ratings intact.  
Why: Do this last, and only once you're happy the backup works — an uninstall wipes the SQLite file, so the cloud copy is all there is.

