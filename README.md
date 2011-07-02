This is a set of (at least at the moment) shell scripts that manage a process whereby code can be modified from and uploaded to [Dropbox](http://www.dropbox.com/), at which point a Mac running these scripts will notice the Dropox changes, check those changes into git, build a new iOS executable from the git changes, push that executable to a web page, and send the user a push notification to come get it.

There's a [video demo](http://www.youtube.com/watch?v=kJ9ctI8UBLA) up on YouTube, a [presentation](http://www.slideshare.net/carlbrown/developing-ios-apps-on-your-ipad-with-xcab) on SlideShare that I gave last Thursday to the Austin [CocoaCoder](http://www.cocoacoder.org/CocoaCoder.org/Hello.html) group, if you want more information.

It's MIT licensed, so feel free to try it out and send me feedback or updates via fork requests.  I find it useful, and I hope other people will, too.

I'm currently using BetaBuilder to generate the ipa file, and using the [Boxcar](http://boxcar.io/) API to send push notifications.

You'll need to get [the command line version of BetaBuilder](git://github.com/sgruby/iOS-BetaBuilder.git), at least at the moment.

I've done some cleanup so it should be conceivable that it should work on someone else's machine (although, as far as I know, so far it never has).

I think what I've decided to do long term is to make a Mac MenuBar (NSStatusItem) based App and use NSTimer instead of running it from cron, and then work on moving a piece of it at a time from bash to Cocoa.  Then I'll make an iOS app to simplify what you have to do on the iOS side.

I just (1 July 2011) pushed a version that has preliminary TestFlight support. It still needs work.  For example, it doesn't check return codes from the TestFlight API, so XCAB doesn't know whether the upload worked or not, and right now TestFlight is updated *in addition to* BetaBuilder instead of *as an alternative to* BetaBuilder (it seems to me that people would most likely use either one or the other but not both).  I will be working on it more.
