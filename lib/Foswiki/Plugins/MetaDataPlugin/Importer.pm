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

package Foswiki::Plugins::MetaDataPlugin::Importer;

use strict;
use warnings;

use Foswiki::Func ();
use Error qw(:try);
#use Data::Dump qw(dump);
use Spreadsheet::Read ();
use Foswiki::Plugins::SpreadsheetReaderPlugin::Utils;

use constant TRACE => 0; # toggle me

##############################################################################
sub _writeDebug {
  return unless TRACE;
  print STDERR "MetaDataPlugin::Importer - $_[0]\n";
  #Foswiki::Func::writeDebug("MetaDataPlugin::Importer - $_[0]") if TRACE;
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
sub jsonRpcImport {
  my ($this, $request) = @_;

  _writeDebug("called jsonRpcImport");

  my $web = $this->{session}{webName};
  my $topic = $request->param('topic') || $this->{session}{topicName};
  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  _writeDebug("topic=$web.$topic");

  my ($topicObj) = Foswiki::Func::readTopic($web, $topic);

  my $currentWikiName = Foswiki::Func::getWikiName();

  throw Error::Simple("Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $currentWikiName, undef, $topic, $web, $topicObj);

  throw Error::Simple("Access denied")
    unless Foswiki::Func::checkAccessPermission("CHANGE", $currentWikiName, undef, $topic, $web, $topicObj);

  my $attachment = $request->param("attachment");
  throw Error::Simple("no attachment specified") unless defined $attachment;

  ($attachment) = Foswiki::Func::sanitizeAttachmentName($attachment);
  _writeDebug("attachment=$attachment");

  throw Error::Simple("attachment not found") unless Foswiki::Func::attachmentExists($web, $topic, $attachment);

  my $filePath = $Foswiki::cfg{PubDir} . '/' . $web . '/' . $topic . '/' . $attachment;
  _writeDebug("filePath=$filePath");

  throw Error::Simple("file not found") unless -e $filePath;

  my $theMetaDataName = $request->param("metadata");
  throw Error::Simple("no metadata specified") unless defined $theMetaDataName;
  $theMetaDataName = uc($theMetaDataName);

  my $formDef = $this->{core}->getFormDef($theMetaDataName);
  throw Error::Simple("form definition not found for $theMetaDataName") unless defined $formDef;

  my $theUnique = $request->param("unique");
  throw Error::Simple("no unique parameter specified") unless defined $theUnique; 
  _writeDebug("unique=$theUnique");

  my @metaDataRecords = ();

  my $opts = {
    strip => 1,
    #dtfmt => "dd.mm.yyyy",  # SMELL: doesn't seem to make any difference
    attr => 1,
  };
  my $password = $request->param("password");
  $opts->{password} = $password if defined $password;
  $opts->{sep} = $request->param("sep");
  $opts->{quote} = $request->param("quote");

  my $book = Spreadsheet::Read->new($filePath, $opts);
  my $theSheets = $request->param("sheets") // $request->param("sheet");
  my $maxSheets = $book->sheets;
  #_writeDebug("maxSheets=$maxSheets");

  throw Error::Simple("spreadsheet contains no sheets") unless $maxSheets > 0;

  my @selectedSheets = ();
  if (defined $theSheets) {
    if ($theSheets eq 'all') {
      push @selectedSheets, $_ foreach 1 .. $maxSheets;
    } else {
      @selectedSheets = split(/\s*,\s*/, $theSheets);
    }
  } else {
    push @selectedSheets, 1;
  }
  #_writeDebug("selectedSheets=@selectedSheets");

  my $theRows = $request->param("rows") // 'all';
  my $theCols = $request->param("cols") // 'all';
  my $theStrip = Foswiki::Func::isTrue($request->param("strip"), 1);
  my $theDecode = Foswiki::Func::isTrue($request->param("decode"), 1);
  my $theDry = Foswiki::Func::isTrue($request->param("dry"), 0);

  my $theLimit = $request->param("limit");
  my $theSkip = $request->param("skip") || 0;

  foreach my $sheetId (@selectedSheets) {
    my $sheet = $book->sheet($sheetId);
    my $maxRows = $sheet->maxrow;
    my $maxCols = $sheet->maxcol;
    _writeDebug("reading sheet $sheetId, maxRows=$maxRows, maxCols=$maxCols");

    my @selectedRows = expandRange($theRows, $maxRows);
    my @selectedCols = expandRange($theCols, $maxCols);

    my @headers = ();
    my $isHeader = 1;
    my $rowIndex = 0;
    my %data = ();

    foreach my $row (@selectedRows) {

      if (!$isHeader && $theSkip && $rowIndex < $theSkip) {
        $rowIndex++;
        next;
      }
      _writeDebug("processing header row") if $isHeader;
      _writeDebug("processing row $rowIndex") unless $isHeader;

      my $colIndex = 0;
      my $enabled = 1;

      foreach my $col (@selectedCols) {
        my $key = $book->cr2cell($col, $row);
        my $attr = $sheet->attr($key);
        my $enc = $attr->{enc};
        my $val = $sheet->cell($key);

        if (defined $enc && $theDecode && $val ne "") {
          try {
            _writeDebug("decoding value with $enc");
            $val = Encode::decode($enc, $val);
          } catch Error with {
            print STDERR "ERROR: encoding error at row=$row, col=$col, value=$val, enc=$enc\n";
          };
        }

        if ($theStrip) {
          $val =~ s/^\s+//g;
          $val =~ s/\s+$//g;
        }

        my $type = $attr->{type} || '';
        #_writeDebug("$key=$val, type=$type, enc=" . ($enc // 'undef'));

        if ($isHeader) {
          my $header = $val;
          if ($theStrip) {
            $header =~ s/^\s+//g;
            $header =~ s/\s+$//g;
          }
          $header = Foswiki::Form::fieldTitle2FieldName($header);
          my $mappedHeader = $request->param($header);
          if (defined $mappedHeader) {
            _writeDebug("mapping $header to $mappedHeader");
            $header = $mappedHeader;
          } else {
            _writeDebug("found header $header");
          }
          push @headers, $header if defined $header && $header ne "";
        } else {
          my $header = $headers[$colIndex++];
          if (defined $header) {
            my $include = $request->param($header . "_include");
            my $exclude = $request->param($header . "_exclude");
            $enabled = 0 if defined($include) && $val !~ /$include/i;
            $enabled = 0 if defined($exclude) && $val =~ /$exclude/i;
          }

          $data{$header} = $val if $enabled && defined $header && $header ne "";
        }
      }

      if (!$isHeader && $enabled) {
        throw Error::Simple("unique parameter not found in data") unless defined $data{$theUnique};
        next if $data{$theUnique} eq '';

        my $record = $this->findRecord($topicObj, $theMetaDataName, $theUnique, $data{$theUnique});
        
        if ($record) {
          $record = $this->updateRecord($topicObj, $record, \%data, $formDef);
        } else {
          $record = $this->createRecord($topicObj, \%data, $formDef);
        }

        _writeDebug("record did not update") unless defined $record;
        push @metaDataRecords, $record if defined $record;
        $rowIndex++;
      }

      last if $theLimit && $rowIndex >= $theLimit;
      $isHeader = 0;
    }
  }

  my $maxId = $this->{core}->getMaxId($theMetaDataName, $topicObj)+1;
  foreach my $record (@metaDataRecords) {
    if ($record->{name} eq 'id') {
      $record->{name} = "id".($maxId++);
    }
    $topicObj->putKeyed($theMetaDataName, $record);
  }

  #_writeDebug("records=".dump(\@metaDataRecords));

  my $count = scalar(@metaDataRecords);
  $topicObj->save() if $count && !$theDry;

  return $count;
}

sub findRecord {
  my ($this, $topicObj, $metaDataName, $field, $value) = @_;
  
  my $record;

  if ($field eq 'name') {
    $record = $topicObj->get($metaDataName, $value);
  } else {
    foreach my $r ($topicObj->find($metaDataName)) {
      next unless defined $r->{$field};
      if ($r->{$field} eq $value) {
        $record = $r;
        last;
      }
    }
  }

  return $record;
}

sub updateRecord {
  my ($this, $topicObj, $record, $data, $formDef) = @_;

  my $cUID = Foswiki::Func::getCanonicalUserID();
  my $request = Foswiki::Func::getRequestObject();
  my $hasUpdated = 0;


  foreach my $fieldDef (@{$formDef->getFields()}) {
    my $name = $fieldDef->{name};
    my $val = $data->{$name};
    unless (defined $val) {
      _writeDebug("no val found for $name");
      next;
    }

    my $keyValues = {
      value => $val
    };
    $fieldDef->createMetaKeyValues($request, $topicObj, $keyValues);
    $val = $keyValues->{value};

    _writeDebug("$name=$val");

    if (!defined($record->{$name}) || $record->{$name} ne $val) {
      $record->{$name} = $val;
      $hasUpdated = 1;
    }
  }

  return unless $hasUpdated;

  $record->{date} = time();
  $record->{author} = $cUID;

  return $record;
}

sub createRecord {
  my ($this, $topicObj, $data, $formDef) = @_;

  _writeDebug("called createMetaData()");
  my $record = $this->{core}->createRecord();
  return $this->updateRecord($topicObj, $record, $data, $formDef);
}

1;
