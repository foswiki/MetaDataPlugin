# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# MetaDataPlugin is Copyright (C) 2019-2025 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::MetaDataPlugin::Exporter;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Time ();
use Error qw(:try);
#use Data::Dump qw(dump);
use Spreadsheet::Write ();
use File::Temp ();
use File::Path qw(make_path);

use constant TRACE => 0; # toggle me

##############################################################################
sub _writeDebug {
  return unless TRACE;
  print STDERR "MetaDataPlugin::Exporter - $_[0]\n";
  #Foswiki::Func::writeDebug("MetaDataPlugin::Exporter - $_[0]") if TRACE;
}

##############################################################################
sub new {
  my ($class, $session, $core) = @_;

  my $this = bless({
    session => $session,
    core => $core,
  }, $class);

  return $this;
}

##############################################################################
sub finish {
  my $this = shift;

  undef $this->{session};
  undef $this->{core};
}

##############################################################################
sub jsonRpcExport {
  my ($this, $request ) = @_;

  _writeDebug("called jsonRpcExport");

  my $web = $this->{session}{webName};
  my $topic = $request->param('topic') || $this->{session}{topicName};
  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  _writeDebug("topic=$web.$topic");

  my ($topicObj) = Foswiki::Func::readTopic($web, $topic);

  my $currentWikiName = Foswiki::Func::getWikiName();

  throw Error::Simple("Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $currentWikiName, undef, $topic, $web, $topicObj);

  my $theMetaDataName = $request->param("metadata");
  throw Error::Simple("no metadata specified") unless defined $theMetaDataName;
  my $metaDataKey = uc($theMetaDataName);

  my $formDef = $this->{core}->getFormDef($metaDataKey);
  throw Error::Simple("form definition not found for $metaDataKey") unless defined $formDef;

  _writeDebug("metadata=$metaDataKey");

  my $attachment = $request->param("attachment");
  my $fileName;
  my $filePath;
  my $fh;

  if (defined $attachment && $attachment ne "") {
    throw Error::Simple("Access denied")
      unless Foswiki::Func::checkAccessPermission("CHANGE", $currentWikiName, undef, $topic, $web, $topicObj);

    my $suffix = $attachment =~ /\.(\w+)$/ && $1;
    $suffix = ".$suffix" if $suffix;
    my $fh = File::Temp->new(SUFFIX => $suffix);
    binmode($fh);

    $fileName = $attachment;
    $filePath = $fh->filename;
  } else {
    $fileName = 'genmetadata_' . $theMetaDataName . '.xlsx';
    my $dir = $Foswiki::cfg{PubDir} . '/' . $web . '/' . $topic;
    make_path($dir, {
      mode => $Foswiki::cfg{Store}{dirPermission}
    }) unless -d $dir;
    $filePath = $dir . '/' . $fileName;
  }

  _writeDebug("filePath=$filePath");

  my $theSort = $request->param("sort");

  my @metaDataRecords = $topicObj->find($metaDataKey);
  if (defined $theSort) {
    _writeDebug("sort=$theSort");

    throw Error::Simple("unknown formfield $theSort used for sorting") unless $formDef->getField($theSort);
    my @sorting = ();
    my $isNum = 1;
    foreach my $record (@metaDataRecords) {
      my $val = $record->{$theSort};

      push @sorting, [
        $record,
        $val,
      ]; 

      $isNum = 0 unless $val =~ /^\s*([+-]?\d+(\.\d+)?)?\s*$/;
      #_writeDebug("val=$val, isNum=$isNum");
    }

    
    if ($isNum) {
      @metaDataRecords = map { $_->[0] } sort { $a->[1] <=> $b->[1] } @sorting;
     } else {
      @metaDataRecords = map { $_->[0] } sort { $a->[1] cmp $b->[1] } @sorting;
    }
  }

  #_writeDebug(dump(\@metaDataRecords));

  my $sp = Spreadsheet::Write->new(
    file => $filePath,
    styles => {
      header => { font_weight => 'bold' },
    }
  );

  # write header
  my @headerRow = ();
  foreach my $fieldDef (@{$formDef->getFields()}) {
    my $name = $fieldDef->{name};
    my $title = $fieldDef->{title} || $name;
    my $width = $fieldDef->{size} || 10;
    $width =~ s/^\s*(\d+).*$/$1/;
    $title =~ s/<nop>//g;
    _writeDebug("header=$title, width=$width");
    push @headerRow, {
      content => $title,
      style => "header",
      width => $width,
    }
  }
  push @headerRow, {
    content => "Author",
    style => "header",
    width => 25,
  };
  push @headerRow, {
    content => "Date",
    style => "header",
    width => 20,
  };
  $sp->addrow(@headerRow);

  foreach my $record (@metaDataRecords) {
    #_writeDebug("reading record $theSort=$record->{$theSort}");

    my @row = ();
    foreach my $fieldDef (@{$formDef->getFields()}) {
      my $fieldValue = $record->{$fieldDef->{name}};

      # get default value
      unless (defined $fieldValue && $fieldValue ne "") {
        if ($fieldDef->can('getDefaultValue')) {
          $fieldValue = $fieldDef->getDefaultValue() // '';
        } 
      }

      # TODO: add more control on how the field values are returned.
      # for now, get the display value for some types, not all
      $fieldValue = $fieldDef->getDisplayValue($fieldValue) if $fieldDef->{type} =~ /date/; 

      push @row, $fieldValue;
    }

    my $author = Foswiki::Func::getWikiName($record->{author});
    if ($author) {
      $author = Foswiki::Func::getTopicTitle($Foswiki::cfg{UsersWebName}, $author);
    } else {
      $author = 'unknown';
    }

    push @row, $author;
    push @row, Foswiki::Time::formatTime($record->{date}, '$day $mon $year - $hour:$min');

    $sp->addrow({ content => \@row });
  }

  $sp->close();

  if (defined $attachment && $attachment ne "") {
    my @stats = stat $filePath;
    my $fileSize = $stats[7];
    my $fileDate = $stats[9];

    _writeDebug("filePath=$filePath, fileSize=$fileSize, fileDate=$fileDate");

    $topicObj->attach(
      name => $fileName,
      file => $filePath,
      stream => $fh,
      filesize => $fileSize,
      filedate => $fileDate,
      minor => 1,
      dontlog => 1,
      nohandlers => 1,
      comment => 'Auto-attached by MetaDataPlugin',
    );
  }

  my $redirect = Foswiki::Func::isTrue($request->param("redirect"), 0);
  _writeDebug("redirect=$redirect");

  if ($redirect) {
    my $url = $Foswiki::cfg{PubUrlPath} . '/' . $web . '/' . $topic . '/' . $fileName . '?t=' . time();
    Foswiki::Func::redirectCgiQuery($request, $url);
    return "";
  }

  return Foswiki::Func::getPubUrlPath($web, $topic, $fileName, absolute => 1);
}

1;
