# Rationale & Approach

## Offline for LiveView

LiveView is great. Offline is also great.

Fog of War is an approach to fairly easy offline, which can work for a wide variety of apps.

* [Fog of War's approach](#fog-of-war)
* [LiveView is great](#liveview-is-great)
* [Offline is great](#liveview-is-great)

## Fog of War

Fog of War is an idiom from old Real-Time Strategy games. Like an explored part of a game map, it shows what was there the last time you looked!

Specifically, if you're offline, it shows the last markup that the LiveView loaded with.

Unvisited screens are still unavailable, but you can style links to them gracefully. And, for mobile, where the first visit might be while offline, you can create a bundle of important screens to 'pre-explore' the map.

## LiveView is great

If you're reading this, you might already like LiveView. But most apps are not using LiveView, and it feels polite for us to include an explanation, as a kindness to our fellow travelers.

Why is LiveView great? Most apps that do something interesting are online, and have non-trivial server code. And LiveView is the best way to make those interesting apps.

What is the alternative to LiveView? Well, you used to be forced to split the program up.

For instance, when you pick a username in an app, and it automatically checks to see if that name's available as you're typing, you need a separate little program, running in the browser, talking to the server.

Not a big deal at first, right? But **you wouldn't believe just how big and fragmented these programs ended up**.

Especially from about 2010-2020. Eventually, **billion-dollar startups were created whose sole reason to exist was to paper this over that mess with open-source software and lucrative closed-source platforms.**

So, LiveView is great. It connects directly to the server at all times, not just in response to user actions. And it gives you a way to integrate any complex client-side behavior you want -- but to drive it from the server, without splitting your program's brain, or codebases.

## Offline is great

If you care about the user experience, and especially if you want to wrap it in a mobile app, you need to think about offline behavior. (There are those who will say that, if you care about the user experience, you cannot possibly use web technologies extensively in a mobile application. They are not usually saying it because they believe it to be strictly true, but for other reasons).

For instance, if you install an app from an App Store, and open it offline, it is **reasonable to expect** that it shows a user a screen that is ready to use, not a spinner. This is even true if that screen requires you to sign in or sign up, a that step that of course won't work when offline.

Sure, **usually**, interesting screens require being online. They're often the most important screens. If a user wants a list of vacation rentals, you shouldn't show them 1-month-old listings the app has cached! So, for a screen like that, it makes sense to pointedly require being online if its contents are more stale than some threshold.

But navigation within the app? Much navigation should still be possible even when offline.

The creator of the app knows what screens make sense to have cached and available for navigation locally, and which ones need to show some graceful offline indication.
