# Perl package Game-MarbleRun (repository marblerun)

The aim of Game-MarbleRun is to register marble run tracks built with
GraviTrax® from Ravensburger and to be able to rebuild and visualize them.
Marble run tracks can be imported from a file into a database and exported
for the exchange with others.

Depending on the language environment and available localizations the output
of the program is in english or according to the current locale.
Only german is fully supported right now. A french localization file `fr.po`
contains most element and set names only. Further language files can be
generated using the script `make_gravi_po_file`

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

This module requires these other non core modules and libraries:

  DBI
  DBD::SQLite
  Locale::Maketext::Lexicon
  SVG
  Image::LibRSVG (only if svg_to_png is used to convert svg to png)

## CONTACT

### AUTHOR
If you found bugs or have marble runs you like to share then you can contact
me by email: Wolfgang Friebel, <wp.friebel@gmail.com>
If you have ideas for improvements, can provide translations or like to
contribute code or patches then I would like to hear from you as well.

## COPYRIGHT AND LICENCE

Copyright (C) 2020, 2021 by Wolfgang Friebel

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.28.1 or,
at your option, any later version of Perl 5 you may have available.
