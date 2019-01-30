# See bottom of file for license and copyright information
package Foswiki::Plugins::MetaDataPlugin::JQuery;
use strict;
use warnings;

use Foswiki::Func();
use Foswiki::Plugins::JQueryPlugin::Plugin;
our @ISA = qw( Foswiki::Plugins::JQueryPlugin::Plugin );

sub new {
  my $class = shift;

  my $this = bless(
    $class->SUPER::new(
      name => 'MetaDataPlugin',
      version => '1.0',
      author => 'Michael Daum',
      homepage => 'http://foswiki.org/extensions/MetaDataPlugin',
      puburl => '%PUBURLPATH%/%SYSTEMWEB%/MetaDataPlugin',
      css => ['metadata.css'],
      javascript => ['metadata.js'],
      i18n => $Foswiki::cfg{SystemWebName} . "/MetaDataPlugin/i18n",
      dependencies => ['ui::dialog', 'ui::button', 'validate', 'form', 'jsonrpc'],
    ),
    $class
  );

  return $this;
}

sub init {
  my $this = shift;

  Foswiki::Func::readTemplate("metadataplugin");

  return unless $this->SUPER::init();
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2011-2019 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

Additional copyrights apply to some or all of the code in this
file as follows:

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.

