# Perl package Game-MarbleRun (repository marblerun)

The aim of Game-MarbleRun is to register marble run tracks built with
GraviTrax® from Ravensburger and to be able to rebuild and visualize them.
The tracks are coded in a text file that allows for a very compact notation.
The format is described in a document included in the package. The track
notations are parsed, checked for errors and stored in a (sqlite) database.
The text files can be freely exchanged with others and do not need a central
storage on any server. A script `gravi`, that is included in the package does the
checking and storing of the text files as well as the generation of track
descriptions in a human friendly format and the output of pictures showing
the layout of the track. The pictures (plain or animated view) in the svg
format can best be viewed using web browsers.

Depending on the language environment and available localizations the output
of the program is in english or according to the current locale.
Only german is fully supported right now. A french localization file `fr.po`
contains most element and set names only. Further language files can be
generated using the script `make_gravi_po_file`

This package is work in progress, for many even complicated tracks it has been
proven to produce correct descriptions and for several tracks a basic animation
is working.

## INSTALLATION

To install this module type the following:
```
   perl Makefile.PL
   make
   make test
   make install
```
## USAGE

The package contains a program `gravi` to manage the marble runs

## DEPENDENCIES

This module requires these other non core modules and libraries, which can be
installed using the Linux or MacOS package managers or can be fetched from CPAN:

  DBI
  DBD::SQLite
  Locale::Maketext::Lexicon
  SVG

## CONTACT

### AUTHOR
If you found bugs or have marble runs you like to share then you can contact
me. If you have ideas for improvements, can provide translations or like to
contribute code or patches then I would like to hear from you as well.
If you built a marble track with the official Gravitrax App and have
difficulties to translate it in the notation used here, I can try to help.
In this case please do mail me your (buggy) file containing the attempt to
note down the track and if possible an Gravitrax identifier where I can
see the track you built. The identifier and the code will not be distributed
further in any form and all info on my side gets deleted as soon as the issue
is fixed.

## COPYRIGHT AND LICENCE

Copyright (C) 2020-2025 by Wolfgang Friebel

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.28.1 or,
at your option, any later version of Perl 5 you may have available.
