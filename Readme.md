# ETH AOS/Bluebottle System Sources

This is the source code of the last CrazyFresh release of the ETH AOS/Bluebottle System, dated July 23, 2007, in plain ISO 8859-1 UTF-8 text files.

The following ZIP files with the source code have been downloaded from [the archived bluebottle.ethz.ch website](https://web.archive.org/web/20071011134937/http://bluebottle.ethz.ch:80/dlcrazy.html) on 2023-12-30.

- AosSysSrc.zip, 141 Mod, latest 2007-06-26
- AosAppsSrc.zip, 401 Mod, latest 2007-06-26
- AosOberonSrc.zip, 92 Mod, latest 2007-03-28
- AosGadSrc.zip, 116 Mod, latest 2007-06-25
- AosOberonAppsSrc.zip, 131 Mod, latest 2005-06-30

The files have been converted from the proprietary Oberon to plain UTF-8 format using tools from [here](https://github.com/rochus-keller/Oberon).

Corrected all transformation and syntax errors besides ~30 files in Apps.

The following language changes were observed in the source code:
- Procedures return any type, not only Qualident (replaced by regular typedef)
- FINALLY clause in procedure body (not considered)


By the end of 2005, the main contributors of the AOS/Bluebottle system (Pieter Johannes Muller, Patrik Reali and Thomas Martin Frey) were no longer at ETH, which is likely the reason why there was no later "Current" release.

"Crazy-Fresh" releases are described as "Never tested, never booted but as fresh as it can be". They seem to be the result of student projects. The language report was not updated, so the language modifications are unspecified.


