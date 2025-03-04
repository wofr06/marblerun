# Store marble runs, generate build instructions and visualize runs

A program `gravi` has been written to support various tasks around marble run
tracks built with GraviTrax® from Ravensburger.

With the help of this program marble tracks can be described using a very
compact notation and saved in a short text file. The format is described
in a document included in the package. The track notations are parsed,
checked for errors and stored in a (sqlite) database.

The text files can be freely exchanged with others and do not need a central
storage on any server.

Using the script `gravi`, building instructions in a human readable form
can be generated for the tracks stored in the database. Schematic drawings
can be generated as well to visually check the correctness of the tracks and
help in rebuilding stored tracks. The generated pictures are in the svg format
and can best be viewed using web browsers. Optionally the marbles can be
animated and show the movement of the marbles. 


The program `gravi` hs been written in perl and does make use of the package
Game::MarbleRun, which is contained in this repository.

Depending on the language environment and available localizations the output
of the program is in english or according to the current locale.
Only german is fully supported right now. A french localization file `fr.po`
contains most element and set names only. Further language files can be
generated using the script `make_gravi_po_file`

This package is work in progress, for many even complicated tracks it has been
proven to produce correct descriptions and for several tracks a basic animation
is working.

## INSTALLATION

To install the program `gravi` and the required module type the following:
```
   perl Makefile.PL
   make
   make test
   make install
```
For windows users who do not want to install perl a standalone executable is
provided on the web. For details please consult the documentation.

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
