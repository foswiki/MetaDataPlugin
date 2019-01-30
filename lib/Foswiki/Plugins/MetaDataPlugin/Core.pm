# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# MetaDataPlugin is Copyright (C) 2011-2019 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::MetaDataPlugin::Core;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Meta ();
use Foswiki::Form ();
use Foswiki::Time ();
use Foswiki::Form::Label ();
use Foswiki::Form::Text ();
use Foswiki::Form::Date ();
use Foswiki::Plugins::JQueryPlugin ();
use Error qw( :try );

use constant TRACE => 0; # toggle me

##############################################################################
sub writeDebug {
  return unless TRACE;
  print STDERR "MetaDataPlugin::Core - $_[0]\n";
  #Foswiki::Func::writeDebug("MetaDataPlugin::Core - $_[0]") if TRACE;
}

##############################################################################
sub new {
  my ($class, $session) = @_;

  #writeDebug("called new()");

  my $this = bless({
    session => $session,
  }, $class);

  #writeDebug("done new()");

  return $this;
}

##############################################################################
sub getQueryParser {
  my $this = shift;

  #writeDebug("called getQueryParser()");

  unless (defined $this->{_queryParser}) {
    require Foswiki::Query::Parser;
    $this->{_queryParser} = new Foswiki::Query::Parser();
  }

  #writeDebug("done getQueryParser()");
  return $this->{_queryParser};
}

##############################################################################
sub registerDeleteHandler {
  my ($this, $function, $options) = @_;

  #writeDebug("called registerDeleteHandler()");

  push @{$this->{deleteHandler}}, {
    function => $function,
    options => $options,
  };

  #writeDebug("done registerDeleteHandler()");
}

##############################################################################
sub registerSaveHandler {
  my ($this, $function, $options) = @_;

  #writeDebug("called registerSaveHandler()");

  push @{$this->{saveHandler}}, {
    function => $function,
    options => $options,
  };

  #writeDebug("done registerSaveHandler()");
}

##############################################################################
sub NEWMETADATA {
  my ($this, $params) = @_;

  #writeDebug("called NEWMETADATA()");
  Foswiki::Plugins::JQueryPlugin::createPlugin("metadataplugin");

  my $theMetaData = lc($params->{_DEFAULT} || $params->{meta} // '');
  my $theWarn = Foswiki::Func::isTrue($params->{warn}, 0);

  my $metaDataKey = uc($theMetaData);
  my $metaDataDef = $Foswiki::Meta::VALIDATE{$metaDataKey};
  return ($theWarn?inlineError("can't find meta data definition for $metaDataKey"):'') unless defined $metaDataDef;

  my $theTitle = $params->{title};
  my $theButtonTitle = $params->{buttontitle};
  my $theFormat = $params->{format};
  my $theTemplate = $params->{template} || 'metadata::new';
  my $theTopic = $params->{topic} || $this->{session}{webName}.'.'.$this->{session}{topicName};
  my $theMap = $params->{map} // '';
  my $theIcon = $params->{icon} || 'fa-plus';
  my $theIncludeAttr = $params->{includeattr} // '';
  my $theExcludeAttr = $params->{excludeattr} // '';
  my $theAnchor = $params->{anchor} // '';

  foreach my $map (split(/\s*,\s*/, $theMap)) {
    $map =~ s/\s*$//;
    $map =~ s/^\s*//;
    if ($map =~ /^(.*)=(.*)$/) {
      $params->{$1.'_title'} = $2;
    }
  }

  my @mapping = ();
  my @values = ();
  foreach my $key (keys %$params) {
    my $val = $params->{$key};
    if ($key =~ /_title$/) {
      $key =~ s/_title$//;
      # TODO: do we need to rewrite the key here as well
      push @mapping, $key.'='.$val;
    } elsif ($key =~ /_value$/) {
      $key =~ s/_value$//;
      push @values, 'META:'.uc($theMetaData).':id:'.$key.'='.$val;
    }
  }
  $theMap = join(",", @mapping);
  my $theValues = join("&", @values);

  $theTitle = '%MAKETEXT{"New [_1]" args="'.ucfirst($theMetaData).'"}%' unless defined $theTitle;
  $theButtonTitle = $theTitle unless defined $theButtonTitle;

  my ($web, $topic) = Foswiki::Func::normalizeWebTopicName($this->{session}{webName}, $theTopic);
  $theTopic = "$web.$topic";

  my $wikiName = Foswiki::Func::getWikiName();

  return ($theWarn?inlineError("Error: access denied to change $web.$topic"):'')
    if !Foswiki::Func::checkAccessPermission("VIEW", $wikiName, undef, $topic, $web) ||
       !Foswiki::Func::checkAccessPermission("CHANGE", $wikiName, undef, $topic, $web);


  $theFormat = Foswiki::Func::expandTemplate($theTemplate) unless defined $theFormat;
  $theFormat =~ s/%topic%/$theTopic/g;
  $theFormat =~ s/%meta%/$theMetaData/g;
  $theFormat =~ s/%title%/$theTitle/g;
  $theFormat =~ s/%buttontitle%/$theButtonTitle/g;
  $theFormat =~ s/%map%/$theMap/g;
  $theFormat =~ s/%values%/$theValues/g;
  $theFormat =~ s/%icon%/$theIcon/g;
  $theFormat =~ s/%includeattr%/$theIncludeAttr/g;
  $theFormat =~ s/%excludeattr%/$theExcludeAttr/g;
  $theFormat =~ s/%anchor%/$theAnchor/g;

  #writeDebug("done NEWMETADATA()");
  
  return $theFormat;
}

##############################################################################
sub RENDERMETADATA {
  my ($this, $params) = @_;

  writeDebug("called RENDERMETADATA()");
  Foswiki::Plugins::JQueryPlugin::createPlugin("metadataplugin");

  my $metaData = $params->{_DEFAULT};
  my $topic = $params->{topic} || $this->{session}{topicName};
  my $web = $params->{web} || $this->{session}{webName};
  my $warn = Foswiki::Func::isTrue($params->{warn}, 1);
  my $rev = $params->{revision};

  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  my $action = $params->{action} || 'view';
  my $wikiName = Foswiki::Func::getWikiName();

  my $topicObj = getTopicObject($this, $web, $topic, $rev); 

  $params->{_gotViewAccess} = Foswiki::Func::checkAccessPermission("VIEW", $wikiName, undef, $topic, $web, $topicObj);
  $params->{_gotWriteAccess} = Foswiki::Func::checkAccessPermission("CHANGE", $wikiName, undef, $topic, $web, $topicObj);
  (undef, $params->{_lockedBy}) = Foswiki::Func::checkTopicEditLock($web, $topic);

  $params->{_lockedBy} = Foswiki::Func::getWikiName($params->{_lockedBy})
    if $params->{_lockedBy};

  my $currentWikiName = Foswiki::Func::getWikiName();
  $params->{_isLocked} = ($params->{_lockedBy} ne '' && $params->{_lockedBy} ne $currentWikiName)?1:0;

  writeDebug("currentWikiName=$currentWikiName, lockedBy=$params->{_lockedBy}, isLocked=$params->{_isLocked}");

  return ($warn?inlineError("%MAKETEXT{\"Warning: this topic is locked by user [_1].\" args=\"$params->{_lockedBy}\"}%"):'')
    if $action eq 'edit' && $params->{_isLocked};

  return ($warn?inlineError("Error: access denied to view $web.$topic"):'') 
    if $action eq 'view' && ! $params->{_gotViewAccess};

  return ($warn?inlineError("Error: access denied to change $web.$topic"):'') 
    if $action eq 'edit' && ! $params->{_gotWriteAccess};

  return ($warn?inlineError("Error: unknown action '$action'"):'') unless $action =~ /^(view|edit)$/;

  Foswiki::Func::setTopicEditLock($web, $topic, 1)
    if $action eq 'edit';

  my $result = '';
  if (defined $metaData) {
    $result = $this->renderMetaData($topicObj, $params, $metaData);
  } else {
    foreach $metaData ($this->getKnownMetaData) {
      next unless $topicObj->find($metaData);
      $result .= $this->renderMetaData($topicObj, $params, $metaData);
    }
  }

  return $result;
}

##############################################################################
sub renderMetaData {
  my ($this, $topicObj, $params, $metaData) = @_;

  writeDebug("called renderMetaData()");

  my $query = Foswiki::Func::getRequestObject();

  my $theAction = $params->{action} || 'view';
  my $theFields = $params->{field} || $params->{fields};
  my $theShowIndex = Foswiki::Func::isTrue($params->{showindex});
  my $theFormat = $params->{format};
  my $theHeader = $params->{header};
  my $theFooter = $params->{footer};
  my $theSep = $params->{separator} // '';
  my $theValueSep = $params->{valueseparator} || ', ';
  my $theInclude = $params->{include};
  my $theExclude = $params->{exclude};
  my $theIncludeAttr = $params->{includeattr} // '';
  my $theExcludeAttr = $params->{excludeattr} // '';
  my $theMandatory = $params->{mandatory};
  my $theHiddenFormat = $params->{hiddenformat};
  my $theHideEmpty = Foswiki::Func::isTrue($params->{hideempty}, 0);
  my $theSort = $params->{sort};
  my $theReverse = Foswiki::Func::isTrue($params->{reverse});
  my $theAutolink = Foswiki::Func::isTrue($params->{autolink}, 1);
  my $theFieldFormat = $params->{fieldformat};
  my $theFilter = $params->{filter};
  my $theWarn = Foswiki::Func::isTrue($params->{warn}, 1);
  my $theMap = $params->{map} // '';
  my $theFieldHeader = $params->{fieldheader} // '';
  my $theFieldFooter = $params->{fieldfooter} // '';
  my $theFieldSep = $params->{fieldseparator} // '';
  my $theHidden = $params->{hidden} // '';
  my $theAnchor = $params->{anchor} // '';
  my $theEnabledActions = $params->{enabledactions};
  $theEnabledActions = 'edit,delete,move,duplicate' unless defined $theEnabledActions;
  $theEnabledActions =~ s/^\s+|\s+$//g;
  my %enabledActions = map {lc($_) => 1} split(/\s*,\s*/, $theEnabledActions);
  my $theLimit = $params->{limit} || 0;
  my $theSkip = $params->{skip} || 0;
  my $theNavigation = Foswiki::Func::isTrue($params->{navigation}, 1);

  foreach my $map (split(/\s*,\s*/, $theMap)) {
    $map =~ s/\s*$//;
    $map =~ s/^\s*//;
    if ($map =~ /^(.*)=(.*)$/) {
      $params->{$1.'_title'} = $2;
    }
  }

  # rebuild the mapping string
  my @mapping = ();
  foreach my $key (keys %$params) {
    if ($key =~ /_title$/) {
      my $val = $params->{$key};
      $key =~ s/_title$//;
      push @mapping, $key.'='.$val;
    }
  }
  $theMap = join(",", @mapping);

  my %includeMap = ();
  if (defined $theInclude) {
    foreach my $item (split(/\s*,\s*/, $theInclude)) {
      $includeMap{$item} = 1;
    }
  }

  my %excludeMap = ();
  if (defined $theExclude) {
    foreach my $item (split(/\s*,\s*/, $theExclude)) {
      $excludeMap{$item} = 1;
    }
  }

  if (defined $theFilter) {
    $theInclude = ''; # dummy
    %excludeMap = ();
    %includeMap = ();
    my $queryParser = $this->getQueryParser();
    my $error;
    my $query = "'".$topicObj->getPath()."'/META:".uc($metaData)."[".$theFilter."].name";
    try {
      my $node = $queryParser->parse($query);
      my $result = $node->evaluate(tom => $topicObj, data => $topicObj);
      if (defined $result) {
        if (ref($result) ne 'ARRAY') {
          $result = [$result];
        }
        %includeMap = map {$_ => 1} @$result;
      }
    }
    catch Foswiki::Infix::Error with {
      $error = $theWarn?inlineError("Error: " . shift):'';
    };
    return $error if defined $error;
  }


  $theSort = 'name' unless defined $theSort;
  $theSort = '' if $theSort eq 'off';

  my ($formWeb, $formTopic) = $this->getFormOfMetaData($metaData);
  return ($theWarn?inlineError("can't find meta data definition for $metaData"):'') unless defined $formWeb;
  
  writeDebug("formWeb=$formWeb, formTopic=$formTopic");
  my $wikiName = Foswiki::Func::getWikiName();
  return ($theWarn?inlineError("access denied to form definition for <nop>$metaData"):'')
    unless Foswiki::Func::checkAccessPermission("VIEW", $wikiName, undef, $formTopic, $formWeb);

  return ($theWarn?inlineError("form definition for <nop>$metaData not found"):'')
    unless Foswiki::Func::topicExists($formWeb, $formTopic);

  my $formDef;
  try {
    $formDef = new Foswiki::Form($this->{session}, $formWeb, $formTopic);
  } catch Error::Simple with {

    # just in case, cus when this fails it takes down more of foswiki
    Foswiki::Func::writeWarning("MetaDataPlugin::Core::renderMetaData() failed for $formWeb.$formTopic: ".shift);
  } catch Foswiki::AccessControlException with {
    # catch but simply bail out
    #print STDERR "can't access form at $formWeb.$formTopic in renderMetaData()\n";

    # SMELL: manually invalidate the forms cache for a partially build form object 
    if (exists $this->{session}{forms}{"$formWeb.$formTopic"}) {
      #print STDERR "WARNING: bug present in Foswiki::Form - invalid form object found in cache - deleting it manually\n";
      delete $this->{session}{forms}{"$formWeb.$formTopic"};
    }
  };
  
  return ($theWarn?inlineError("can't parse form definition at $formWeb.$formTopic"):'')
    unless defined $formDef;

  my @selectedFields = ();
  if ($theFields) {
    foreach my $fieldName (split(/\s*,\s*/, $theFields)) {
      $fieldName =~ s/^\s+|\s+$//g;
      my $field;
      if ($fieldName eq 'index') {
        $field = new Foswiki::Form::Label(
          session    => $this->{session},
          name       => 'index',
          type       => 'label',
          title      => '#',
          description => '',
        );
      }  elsif ($fieldName eq 'name') {
        $field = new Foswiki::Form::Label(
          session    => $this->{session},
          name       => 'name',
          type       => 'label',
          title      => '#',
          attributes => 'h',
          description => '',
        );
      }  elsif ($fieldName =~ /^(create)?date$/) {
        $field = new Foswiki::Form::Date (
          session    => $this->{session},
          name       => $fieldName,
          title       => $fieldName,
          type       => 'date',
          description => '',
        );
      }  elsif ($fieldName =~ /^(create)?author$/) {
        $field = new Foswiki::Form::Text (
          session    => $this->{session},
          name       => $fieldName,
          title       => $fieldName,
          type       => 'text',
          description => '',
        );
      }  else {
        $field = $formDef->getField($fieldName);
      }
      push @selectedFields, $field if $field;
    }
  } else {
    if ($theShowIndex) {
      my $indexField = new Foswiki::Form::Label(
        session    => $this->{session},
        name       => 'index',
        type       => 'label',
        title      => '#',
        description => '',
      );
      push @selectedFields, $indexField;
    }
    my $nameField = new Foswiki::Form::Label(
        session    => $this->{session},
        name       => 'name',
        type       => 'label',
        title      => '#',
        attributes => 'h',
        description => '',
    );
    push @selectedFields, $nameField;
    foreach my $field (@{$formDef->getFields()}) {
      my $fieldAttrs = $field->{attributes};
      next if $theIncludeAttr && $fieldAttrs !~ /^($theIncludeAttr)$/;
      next if $theExcludeAttr && $fieldAttrs =~ /^($theExcludeAttr)$/;
      push @selectedFields, $field;
    }
  }

  my $name = $params->{name};

  # default formats
  $theMandatory = " <span class='foswikiAlert'>**</span> " unless defined $theMandatory;

  unless (defined $theHeader) {
    if ($theAction eq 'view') {
      if (defined $name) { # single mode
        $theHeader = '<div class=\'foswikiPageForm\'>$n<table class=\'foswikiLayoutTable $class\'><tbody>$n';
      } else {
        $theHeader = '<div class=\'metaDataView'.($params->{_gotWriteAccess}?'':' metaDataReadOnly').'\'>$n<table class="foswikiTable $class"><thead><tr><th>$n'.join(' </th><th>$n', 
          map {
            my $title = $_->{title}; 
            my $name = $_->{name}; 
            defined($params->{$name.'_title'})?$params->{$name.'_title'}:$title
          } 
          grep {$_->{name} ne 'name'}
          @selectedFields).' </th></tr></thead><tbody>$n';
      }
    } else {
      $theHeader = '<div class=\'metaDataEdit foswikiFormSteps\'>$n';
    }
  }

  unless (defined $theFormat) {
    if ($theAction eq 'view') {
      if (defined $name) { # single mode
        $theFormat = join('', 
          map {
            '$'.$_->{name}
          } 
          grep {$_->{name} ne 'name'}
          @selectedFields);
      } else {
        $theFormat = '<tr class=\'metaDataRow\'><td>$n'.join(' </td><td>$n', 
          map {
            '$'.$_->{name}
          } 
          grep {$_->{name} ne 'name'}
          @selectedFields).' '.($params->{_gotWriteAccess}?'$actions':'').' </td></tr>$n';
      }
    } else {
      $theFormat = '<div class=\'foswikiFormStep $metadata\'>$n<table class=\'foswikiLayoutTable\'>$n'.
        join('$n', map {'$'.$_->{name}} @selectedFields).
        '$n</table></div>';
    }
  }

  unless (defined $theFieldFormat) {
    if ($theAction eq 'view') {
      if (defined $name) { # single mode
        $theFieldFormat = '<tr><th valign=\'top\'>$title:</th><td>$value</td></tr>';
      } else {
        $theFieldFormat = '$value';
      }
    } else {
      $theFieldFormat = '  <tr class="$metadata $name">$n'.
        '    <th valign=\'top\'>$title:$mandatory</th>$n'.
        '    <td>$n$edit$n<div class=\'foswikiFormDescription\'>$description</div></td>'.
        '  </tr>';
    }
  }

  unless (defined $theHiddenFormat) {
    if ($theAction eq 'view') {
      $theHiddenFormat = $theFieldFormat;
    } else {
      $theHiddenFormat = '<input type="hidden" name="$metaname" value="$origvalue" />';
    }
  }

  unless (defined $theFooter) {
    if ($theAction eq 'view') {
      if (defined $name) { # single mode
        $theFooter = '</tbody></table></div>';
      } else {
        $theFooter = '</tbody></table></div>';
      }
    } else {
      $theFooter = '</div>';
    }
  }

  unless (defined $theSep) {
    if ($theAction eq 'view') {
      $theSep = '';
    } else {
      $theSep = '$n<hr />$n';
    }
  }

  my @result = ();
  my @metaDataRecords;
  my $metaDataKey = uc($metaData);
  if (defined $name) {
    my $record;
    if ($name eq 'id') { # create a new record
      $record = {
        name => 'id'
      };
    } else {
      # get it from the store
      $record = $topicObj->get($metaDataKey, $name);
    }
    push @metaDataRecords, $record if defined $record;
  } else {
    push @metaDataRecords, $topicObj->find($metaDataKey);
  }

  # build mapping
  $this->{_mapping} = ();

  # TODO: use handlers
  if ($theAction ne 'edit' && Foswiki::Func::getContext()->{SocialFormfieldsPluginEnabled}) {
    require Foswiki::Plugins::SocialFormfieldsPlugin;
    my $socialCore = Foswiki::Plugins::SocialFormfieldsPlugin::getCore();

    foreach my $record (@metaDataRecords) {
      foreach my $field (@selectedFields) {
        next unless $field;
        my $fieldName = $field->{name};
        next if $fieldName eq 'index';
        my $fieldValue = $record->{$fieldName};
        if (defined $fieldValue && $fieldValue =~ /^social\-(.*)$/) {
          my ($intVal) = $socialCore->getAverageVote($1);
          my $val = $socialCore->convertIntToVal(undef, $field, $intVal); 
          $this->{_mapping}{$fieldValue} = $val;
        }
      }
    }
  }

  # sort and reverse
  $this->sortRecords(\@metaDataRecords, $theSort, $topicObj) if $theSort;
  @metaDataRecords = reverse @metaDataRecords if $theReverse;

  # loop over all meta data records
  my $index = 0;
  foreach my $record (@metaDataRecords) {
    my $row = $theFormat;
    my $name = $record->{name};
    my $title = $name;

    next if defined $theInclude && !defined($includeMap{$name});
    next if defined $theExclude && $excludeMap{$name};

    $index++;
    last if $theLimit && $index > $theLimit;
    next if $theSkip && $index <= $theSkip;

    # loop over all fields of a record
    my @fieldResult = ();
    my %fieldValues = ();
    foreach my $field (@selectedFields) {
      next unless $field;

      my $fieldName = $field->{name};
      my $fieldType = $field->{type};
      my $fieldSize = $field->{size};
      my $fieldAttrs = $field->{attributes};
      my $fieldDescription = $field->{tooltip} || $field->{description};
      my $fieldTitle = $field->{title};
      my $fieldDefiningTopic = $field->{definingTopic};
      my $fieldFormat = $theFieldFormat;

      my $metaFieldName = 'META:'.$metaDataKey.':'.$name.':'.$fieldName; 
      if ($theAction eq 'edit') {
        $field->{name} = $metaFieldName; 
      }

      my $fieldAllowedValues = '';
      # CAUTION: don't use field->getOptions() on a +values field as that won't return the full valueMap...only the value part, but not the title map
      if ($field->can('getOptions') && $field->{type} !~ /\+values/) {
        #writeDebug("can getOptions");
        my $options = $field->getOptions();
        if ($options) {
          #writeDebug("options=$options");
          $fieldAllowedValues = join($theValueSep, @$options);
        }
      } else {
        #writeDebug("can't getOptions ... fallback to field->{value}");
        # fallback to field->value
        my $options = $field->{value};
        if ($options) {
          $fieldAllowedValues = join($theValueSep, split(/\s*,\s*/, $options));
        }
      }
      #writeDebug("fieldAllowedValues=$fieldAllowedValues");

      # get the list of all allowed values without any +values mapping applied
      my $fieldOrigAllowedValues = '';
      if ($field->can('getOptions')) {
        #writeDebug("can getOptions");
        my $options = $field->getOptions();
        if ($options) {
          #writeDebug("options=$options");
          $fieldOrigAllowedValues = join($theValueSep, @$options);
        }
      } else {
        #writeDebug("can't getOptions ... fallback to field->{value}");
        # fallback to field->value
        my $options = $field->{value};
        if ($options) {
          $fieldOrigAllowedValues = join($theValueSep, split(/\s*,\s*/, $options));
        }
      }
      #writeDebug("fieldOrigAllowedValues=$fieldOrigAllowedValues");

      # get the default value
      my $fieldDefault = '';
      if ($field->can('getDefaultValue')) {
        $fieldDefault = $field->getDefaultValue() // '';
      } 

      my $fieldValue;

      if ($fieldName eq 'index') {
        $fieldValue = $index;
      } else {
        $fieldValue = $this->getFieldValue($record, $fieldName);
      }

      if ($fieldName =~ /^(create)?date$/) {
        $fieldValue ||= 0;
        $fieldValue = Foswiki::Func::formatTime($fieldValue);
      } elsif ($fieldName =~ /^(create)?author$/) {
        $fieldValue = 'unknown' unless defined $fieldValue;
        $fieldValue = Foswiki::Func::getWikiName($fieldValue);
      }

      # try not to break foswiki tables
#      if ($theAction eq 'view' && defined($fieldValue)) {
#        $fieldValue =~ s/\n/<br \/>/g;
#      }

      $fieldSize = $params->{$fieldName.'_size'} if defined $params->{$fieldName.'_size'};
      $fieldAttrs = $params->{$fieldName.'_attributes'} if defined $params->{$fieldName.'_attributes'};
      $fieldDescription = $params->{$fieldName.'_tooltip'} if defined $params->{$fieldName.'_tooltip'};
      $fieldDescription = $params->{$fieldName.'_description'} if defined $params->{$fieldName.'_description'};
      $fieldTitle = $params->{$fieldName.'_title'} if defined $params->{$fieldName.'_title'}; 
      $fieldAllowedValues = $params->{$fieldName.'_values'} if defined $params->{$fieldName.'_values'};
      $fieldType = $params->{$fieldName.'_type'} if defined $params->{$fieldName.'_type'};
      $fieldValue = $params->{$fieldName.'_value'} if defined $params->{$fieldName.'_value'}; # or get value from macro invocation
      $fieldDefault = $params->{$fieldName.'_default'} if defined $params->{$fieldName.'_default'};

      my $fieldIsHidden = ($fieldAttrs=~ /h/i || $theHidden && $fieldName =~ /^($theHidden)$/) ? 1 : 0;
      $fieldIsHidden = Foswiki::Func::isTrue($params->{$fieldName.'_hidden'}, 0) if defined $params->{$fieldName.'_hidden'};

      if (defined $params->{$fieldName.'_format'}) {
        $fieldFormat = $params->{$fieldName.'_format'};
      } else {
        $fieldFormat = $theHiddenFormat if $fieldIsHidden;
      }

      my $fieldMandatory = $field->isMandatory?$theMandatory:'';

      if ($theAction eq 'edit') { # or get value from url (highest prio)
        my $urlValue;
        my $key = 'META_'.uc($metaData).'_'.$fieldName;
        if ($field->isMultiValued) {
          my @urlValue = $query->multi_param($key);
          $urlValue = join(", ", @urlValue) if @urlValue;
        } else {
          $urlValue = $query->param($key);
        }
        $fieldValue = $urlValue if defined $urlValue;
      }

      my $fieldAutolink = Foswiki::Func::isTrue($params->{$fieldName.'_autolink'}, $theAutolink);
      my $fieldSort = Foswiki::Func::isTrue($params->{$fieldName.'_sort'});
#      $fieldAllowedValues = sortValues($fieldAllowedValues, $fieldSort) if $fieldSort;

      if ($fieldName ne 'name') {
        next if $theIncludeAttr && $fieldAttrs !~ /^($theIncludeAttr)$/;
        next if $theExcludeAttr && $fieldAttrs =~ /^($theExcludeAttr)$/;
      }

      $fieldValue = $fieldDefault unless defined $fieldValue;
      $fieldDescription = '' unless defined $fieldDescription;
      writeDebug("metaData=$metaData, fieldName=$fieldName, fieldValue=$fieldValue");

      if ($theHideEmpty && $theAction eq 'view' && (!defined($fieldValue) || $fieldValue eq '')) {
        $row =~ s/\$$fieldName//g;
        next;
      }

      # temporarily remap field to another type
      my $fieldClone;
      if (defined($params->{$fieldName.'_type'}) || 
          defined($params->{$fieldName.'_size'}) ||
          $fieldSort) {
        $fieldClone = $formDef->createField(
          $fieldType,
          name          => $field->{name},
          title         => $fieldTitle,
          size          => $fieldSize,
          value         => $fieldAllowedValues,
          tooltip       => $fieldDescription,
          attributes    => $fieldAttrs,
          definingTopic => $fieldDefiningTopic,
          web           => $topicObj->web,
          topic         => $topicObj->topic,
        );
        $field = $fieldClone;
      } 

      my $line = $fieldFormat;
      $line = '<noautolink>'.$line.'</noautolink>' unless $fieldAutolink;

      # some must be expanded before renderForDisplay/renderForDisplay
      $line =~ s/\$values\b/$fieldAllowedValues/g;
      $line =~ s/\$origvalues\b/$fieldOrigAllowedValues/g;
      $line =~ s/\$title\b/$fieldTitle/g;

      # For Foswiki > 1.2, treat $value ourselves to get a consistent
      # behavior across all releases:
      # - patch in (display) value as $value
      # - use raw value as $origvalue
      my $origValue = $fieldValue;
      $line =~ s/\$value([^\(]|$)/\$value(display)\0$1/g;

      my $fieldExtra = '';
      my $fieldEdit = '';

      $fieldValue = "\0" unless defined $fieldValue; # prevent dropped value attr in CGI.pm

      if ($theAction eq 'edit') {
        if ($Foswiki::Plugins::VERSION > 2.0) {
          ($fieldExtra, $fieldEdit) = 
            $field->renderForEdit($topicObj, $origValue);
        } else {
          # pre-TOM
          ($fieldExtra, $fieldEdit) = 
            $field->renderForEdit($topicObj->web, $topicObj->topic, $origValue);
        }
      } else {
        $line = $field->renderForDisplay($line, $fieldValue, {
          bar=>'|', # SMELL: keep bars
          newline=>'$n', # SMELL: keep newlines
          display=>1
        }); # SMELL what about the attrs param in Foswiki::Form; wtf is this attr anyway
      }

      $fieldEdit =~ s/\0//g;
      $fieldValue =~ s/\0//g;
      $line =~ s/\0//g;

      # escape %VARIABLES inside input values
      $fieldEdit =~ s/(<input.*?value=["'])(.*?)(["'])/
        my $pre = $1;
        my $tmp = $2;
        my $post = $3;
        $tmp =~ s#%#%<nop>#g;
        $pre.$tmp.$post;
      /ge;
      $fieldEdit =~ s/(<textarea[^>]*>)(.*?)(<\/textarea>)/
        my $pre = $1;
        my $tmp = $2;
        my $post = $3;
        $tmp =~ s#%#%<nop>#g;
        $pre.$tmp.$post;
      /gmes;

      $line =~ s/\$mandatory/$fieldMandatory/g;
      $line =~ s/\$edit\b/$fieldEdit/g;
      $line =~ s/\$name\b/$fieldName/g;
      $line =~ s/\$metaname\b/$metaFieldName/g;
      $line =~ s/\$type\b/$fieldType/g;
      $line =~ s/\$size\b/$fieldSize/g;
      $line =~ s/\$attrs\b/$fieldAttrs/g;
      $line =~ s/\$default\b/$fieldDefault/g;
      $line =~ s/\$(tooltip|description)\b/$fieldDescription/g;
      $line =~ s/\$title\b/$fieldTitle/g;
      $line =~ s/\$extra\b/$fieldExtra/g;
      $line =~ s/\$origvalue\b/$origValue/g;

      $title = $fieldValue if $fieldName =~ /^(Topic)?Title/i;

      $row =~ s/\$$fieldName\b/$line/g;
      $row =~ s/\$orig$fieldName\b/$fieldValue/g;

      $fieldValues{$fieldName} = {
        value => $line,
        orig => $fieldValue,
      };

      writeDebug("line=$line");
      push @fieldResult, $line;

      # cleanup
      $fieldClone->finish() if defined $fieldClone;
      $field->{name} = $fieldName;
    }
    
    writeDebug("row='$row'");

    $title = $name unless $title;

    my $fieldActions = '';

    if ($params->{_gotWriteAccess}) {
      $fieldActions = Foswiki::Func::expandTemplate("metadata::actions");

      my $fieldEditAction = $enabledActions{edit}?Foswiki::Func::expandTemplate("metadata::action::edit"):"";
      my $fieldDeleteAction = $enabledActions{delete}?Foswiki::Func::expandTemplate("metadata::action::delete"):"";
      my $fieldDuplicateAction = $enabledActions{duplicate}?Foswiki::Func::expandTemplate("metadata::action::duplicate"):"";
      my $fieldMoveAction = $enabledActions{move}?Foswiki::Func::expandTemplate("metadata::action::move"):"";

      my $topic = $topicObj->getPath;
      if (defined $params->{edittitle}) {
        $title = $params->{edittitle};
      } else {
        $title = '%MAKETEXT{"Edit"}% '.$title;
      }

      my $id = "metaDataAction".(int( rand(10000) ) + 1);
      my $navigation = $theNavigation?"on":"off";

      $fieldActions =~ s/\%edit\%/$fieldEditAction/g;
      $fieldActions =~ s/\%duplicate\%/$fieldDuplicateAction/g;
      $fieldActions =~ s/\%delete\%/$fieldDeleteAction/g;
      $fieldActions =~ s/\%move\%/$fieldMoveAction/g;
      $fieldActions =~ s/\%title\%/$title/g;
      $fieldActions =~ s/\%name\%/$name/g;
      $fieldActions =~ s/\%meta\%/$metaData/g;
      $fieldActions =~ s/\%topic\%/$topic/g;
      $fieldActions =~ s/\%map\%/$theMap/g;
      $fieldActions =~ s/\%anchor\%/$theAnchor/g;
      $fieldActions =~ s/\%id\%/$id/g;
      $fieldActions =~ s/\%navigation\%/$navigation/g;
      $fieldActions =~ s/%includeattr%/$theIncludeAttr/g;
      $fieldActions =~ s/%excludeattr%/$theExcludeAttr/g;
    }

    my $fieldResult = '';
    $fieldResult = $theFieldHeader.join($theFieldSep, @fieldResult).$theFieldFooter if @fieldResult;

    $row =~ s/\$actions\b/$fieldActions/g;
    $row =~ s/\$index\b/$index/g;
    $row =~ s/\$id\b/$name/g;
    $row =~ s/\$date\b/$record->{date}/g;
    $row =~ s/\$createdate\b/$record->{createdate}/g;
    $row =~ s/\$fields\b/$fieldResult/g;
    $row =~ s/\$formatTime\((.*?)(?:,\s*'([^']*?)')?\)/Foswiki::Func::formatTime($1, $2)/ge;

    foreach my $fieldName (keys %fieldValues) {
      $row =~ s/\$$fieldName\b/$fieldValues{$fieldName}{value}/g;
      $row =~ s/\$orig$fieldName\b/$fieldValues{$fieldName}{orig}/g;
    }

    push @result, $row unless $theHideEmpty && $row eq '';
  }

  return '' if $theHideEmpty && !@result;

  my $theClass = $params->{class} // '';
  my $result = $theHeader.join($theSep, @result).$theFooter;

  my $formTitle = Foswiki::Func::getTopicTitle($formWeb, $formTopic);

  $index--;
  $result =~ s/\$class/$theClass/g;
  $result =~ s/\$count/$index/g;
  $result =~ s/\$metadata\b/$metaData/g; # the meta data name
  $result =~ s/\$form\b/$formWeb.$formTopic/g; # the meta data definition
  $result =~ s/\$formtitle\b/$formTitle/g; # the meta data definition title
  $result =~ s/\$nop//g;
  $result =~ s/\$n/\n/g;
  $result =~ s/\$perce?nt/%/g;
  $result =~ s/\$dollar/\$/g;
  $result =~ s/\$lockedby/$params->{_lockedBy}/g;
  $result =~ s/\$islocked/$params->{_isLocked}/g;

  #writeDebug("done renderMetaData()");
  return $result;
}

##############################################################################
sub getTopicObject {
  my ($this, $web, $topic, $rev) = @_;

  #writeDebug("called getTopicObject()");

  $web ||= '';
  $topic ||= '';
  $rev ||= '';
  
  $web =~ s/\//\./g;
  my $key = $web.'.'.$topic.'@'.$rev;
  my $topicObj = $this->{_topicObjs}{$key};
  
  unless ($topicObj) {
    ($topicObj, undef) = Foswiki::Func::readTopic($web, $topic, $rev);
    $this->{_topicObjs}{$key} = $topicObj;
  }

  #writeDebug("done getTopicObject()");
  return $topicObj;
}

##############################################################################
sub getKnownMetaData {
  my $this = shift;

  #writeDebug("called getKnownMetaData()");

  unless (defined $this->{_knownMetaData}) {
    $this->{_knownMetaData} = [];
    foreach my $name (sort keys %Foswiki::Meta::VALIDATE) {
      next if $name =~ /^(TOPICINFO|VERSIONS|CREATEINFO|STORAGE|TOPICMOVED|FIELD|FORM|FILEATTACHMENT|TOPICPARENT|PREFERENCE)$/;
      push @{$this->{_knownMetaData}}, $name;
    }
  };

  #writeDebug("done getKnownMetaData()");
  return @{$this->{_knownMetaData}};
}

##############################################################################
sub getFormOfMetaData {
  my ($this, $metaData) = @_;

  my $metaDataKey = uc($metaData);
  my $metaDataDef = $Foswiki::Meta::VALIDATE{$metaDataKey};
  return unless defined $metaDataDef;

  my $formWeb = $this->{session}{webName};
  my $formTopic = $metaDataDef->{form};

  $formTopic = $Foswiki::cfg{SystemWebName}.'.'.ucfirst(lc($metaData)).'Form' 
    unless defined $formTopic;

  ($formWeb, $formTopic) = Foswiki::Func::normalizeWebTopicName($formWeb, $formTopic);

  return ($formWeb, $formTopic);
}

##############################################################################
sub beforeSaveHandler {
  my ($this, $text, $topic, $web, $meta) = @_;

  #writeDebug("called beforeSaveHandler($web.$topic)");

  my $request = Foswiki::Func::getRequestObject();
  my %records = ();

  my $knownMetaDataPattern = join('|', $this->getKnownMetaData);
  #writeDebug("knownMetaDataPattern=$knownMetaDataPattern");

  my $cUID = Foswiki::Func::getCanonicalUserID();

  my $explicitName;
  foreach my $urlParam ($request->param()) {
    unless ($urlParam =~ /^META:($knownMetaDataPattern):(id\d*):(.+)$/) {
      #writeDebug("urlParam does not match: $urlParam");
      next;
    }
    #writeDebug("got urlParam=$urlParam"); 
    my $metaDataName = $1;
    my $name = $2;
    my $field = $3;

    #writeDebug("metaDataName=$metaDataName, name=$name, $field=$field"); 

    # look up cache
    my $record = $records{$metaDataName.':'.$name};

    # first hit
    unless (defined $record) {
    
      if ($name eq 'id') {
        # a new one 
        $record = { 
          name => 'id'.($this->getMaxId($metaDataName, $meta)+1),
          createdate => time,
          createauthor => $cUID,
        };
      } else {
        # go fetch from store
        $record = $meta->get($metaDataName, $name);
      }
    }

    my $value;

    my @value = $request->multi_param($urlParam);
    if (@value) {
      $value = join(", ", @value);
      $value =~ s/,\s*$//g;
    }
    $value = '' unless defined $value;

    #writeDebug("$urlParam=$value");

    # when duplicating a field, the name parameter will have a dummy 'id'
    # to flag that we need to create a new record based on the give one
    # SMELL: doesn't work
    if ($field eq 'name' && $value eq 'id') {
      $value = 'id'.($this->getMaxId($metaDataName, $meta)+1);
    }

    $record->{$field} = $value;
    $records{$metaDataName.':'.$name} = $record;
  }

  #writeDebug("records=".Data::Dumper->Dump([\%records]));

  foreach my $item (keys %records) {
    if ($item =~ /^(.*):(id\d*)$/) {
      my $metaData = $1;
      #my $name = $2;
      my $record = $records{$item};
      $record->{date} = time;
      $record->{author} = $cUID;

      # call save handlers
      if (defined $this->{saveHandler}) {
        foreach my $saveHandler (@{$this->{saveHandler}}) {
          my $function = $saveHandler->{function};
          my $result;
          my $error;

          writeDebug("executing $function");
          try {
            no strict 'refs';
            $result = &$function($web, $topic, $metaData, $record, $saveHandler->{options});
            use strict 'refs';
          } catch Error::Simple with {
            $error = shift;
          };

          print STDERR "error executing saveHandler $function: ".$error."\n" if defined $error;
        }
      }

      $meta->putKeyed($metaData, $record);
    } else {
      die "what's that record: $item"; # never reach
    }
  }

  #writeDebug("done beforeSaveHandler($web.$topic)");
}

##############################################################################
sub getMaxId {
  my ($this, $name, $meta) = @_;

  #writeDebug("called getMaxId()");
  my $maxId = 0;

  foreach my $record ($meta->find($name)) {
    my $id = $record->{name};
    $id =~ s/^id//;
    $maxId = $id if $id > $maxId;
  }

  #writeDebug("getMaxId($name) = $maxId");
  #writeDebug("done getMaxId()");

  return $maxId;
}

##############################################################################
sub jsonRpcLockTopic {
  my ($this, $request) = @_;

  my $web = $this->{session}{webName};
  my $topic = $request->param('topic') || $this->{session}{topicName};
  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  my (undef, $loginName, $unlockTime) = Foswiki::Func::checkTopicEditLock($web, $topic);

  my $wikiName = Foswiki::Func::getWikiName($loginName);
  my $currentWikiName = Foswiki::Func::getWikiName();

  # TODO: localize
  if ($loginName && $wikiName ne $currentWikiName) {
    my $time = int($unlockTime);
    if ($time > 0) {
      throw Foswiki::Contrib::JsonRpcContrib::Error(423, 
        "Topic is locked by $wikiName for another $time minute(s). Please try again later.");
    }
  }

  Foswiki::Func::setTopicEditLock($web, $topic, 1);

  return 'ok';
}

##############################################################################
sub jsonRpcUnlockTopic {
  my ($this, $request) = @_;

  my $web = $request->{session}{webName};
  my $topic = $request->param('topic') || $this->{session}{topicName};
  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  writeDebug("called jsonRpcUnlockTopic($web, $topic)");

  my (undef, $loginName) = Foswiki::Func::checkTopicEditLock($web, $topic);

  return 'ok' unless $loginName; # nothing to unlock

  my $wikiName = Foswiki::Func::getWikiName($loginName);
  my $currentWikiName = Foswiki::Func::getWikiName();

  if ($wikiName ne $currentWikiName) {
    throw Foswiki::Contrib::JsonRpcContrib::Error(500, "Can't clear lease of user $wikiName")
      if $request->param("warn") ne 'off';
  } else {
    Foswiki::Func::setTopicEditLock($web, $topic, 0);
  }

  return 'ok';
}

##############################################################################
sub jsonRpcDelete {
  my ($this, $request) = @_;

  #writeDebug("called jsonRpcDelete()");

  my $web = $this->{session}{webName};
  my $topic = $this->{session}{topicName};

  my $loginName;
  (undef, $loginName) = Foswiki::Func::checkTopicEditLock($web, $topic);
  my $wikiName = Foswiki::Func::getWikiName($loginName) if $loginName;

  my $currentWikiName = Foswiki::Func::getWikiName();
  throw Foswiki::Contrib::JsonRpcContrib::Error(405, "Topic is locked by $wikiName") 
    if $loginName ne '' && $wikiName ne $currentWikiName;

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist") 
    unless Foswiki::Func::topicExists($web, $topic);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("CHANGE", $currentWikiName, undef, $topic, $web, $meta);

  my $name = $request->param('metadata::name') // '';
  my $metaData = $request->param('metadata') // '';

  my $metaDataKey = uc($metaData);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "unknown meta $metaData")
    unless defined $Foswiki::Meta::VALIDATE{$metaDataKey};

  my $record = $meta->get($metaDataKey, $name);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1001, "$metaData name=$name not found")
    unless $record;

  #writeDebug("$this, checking deleteHandler ... ");
  if (defined $this->{deleteHandler}) {
    foreach my $deleteHandler (@{$this->{deleteHandler}}) {
      my $function = $deleteHandler->{function};
      my $result;
      my $error;

      try {
        no strict 'refs';
        $result = &$function($web, $topic, $metaDataKey, $record, $deleteHandler->{options});
        use strict 'refs';
      } catch Error::Simple with {
        $error = shift;
      };

      print STDERR "error executing deleteHandler $function: ".$error."\n" if defined $error;
    }
  }

  # remove this record
  $meta->remove($metaDataKey, $name);

  Foswiki::Func::saveTopic($web, $topic, $meta, $text, {ignorepermissions=>1});
  #writeDebug("done jsonRpcDelete()");

  return 'ok';
}


##############################################################################
sub inlineError {
  my $msg = shift;
  return "<span class='foswikiAlert'>$msg</span>";
}

##############################################################################
sub sortRecords {
  my ($this, $records, $crit, $meta) = @_;

  my $isNumeric = 1;
  my $isDate = 1;
  my %sortCrits = ();
  foreach my $rec (@$records) {
    my $val;
    if ($crit eq 'random') {
      $val = rand();
    } elsif ($crit eq 'name') {
      $val = $rec->{name};
      $val =~ s/^id//;
      $isDate = 0;
    } else {
      $val = '';
      foreach my $key (split(/\s*,\s*/, $crit)) {
        my $v = $this->getFieldValue($rec, $key, $meta);
        next unless defined $v;
        $v =~ s/^\s*|\s*$//g;
        $val .= $v;
      }
    }
    next unless defined $val;

    if ($isNumeric && $val !~ /^(\s*[+-]?\d+(\.?\d+)?\s*)$/) {
      $isNumeric = 0;
    }

    if ($isDate) {
      my $epoch = Foswiki::Time::parseTime($val);
      if (defined $epoch) {
        $val = $epoch;
      } else {
        $isDate = 0;
      }
    }

    $sortCrits{$rec->{name}} = $val;
  }

  $isNumeric = 1 if $isDate;

  #print STDERR "crit=$crit, isNumeric=$isNumeric, isDate=$isDate\n";

  if ($isNumeric) {
    @{$records} = sort {($sortCrits{$a->{name}}||0) <=> ($sortCrits{$b->{name}}||0)} @$records;
  } else {
    @{$records} = sort {lc($sortCrits{$a->{name}}||'') cmp lc($sortCrits{$b->{name}}||'')} @$records;
  }
}

##############################################################################
sub getFieldValue {
  my ($this, $record, $crit, $meta) = @_;

  my $fieldValue = $record->{$crit};
  unless (defined $fieldValue) {
    return unless $meta;
    $fieldValue = Foswiki::Func::decodeFormatTokens($crit);
    $fieldValue =~ s/%id%/$record->{name}/g;
    $fieldValue = Foswiki::Func::expandCommonVariables($fieldValue, $meta->topic, $meta->web, $meta);
  }

  my $mappedValue = $this->{_mapping}{$fieldValue};
  return $mappedValue if defined $mappedValue;
  return $fieldValue;
}

##############################################################################
sub solrIndexTopicHandler {
  my ($this, $indexer, $doc, $web, $topic, $meta, $text) = @_;

  # make sure all metadata for this web has been registered
  my $topics = Foswiki::Func::getPreferencesValue("WEBMETADATA", $web) // '';
  Foswiki::Plugins::MetaDataPlugin::registerMetaData($topics) if $topics;

  my @commonFields = ();
  for my $field (qw(tag category webcat)) {
    my @vals = $doc->values_for($field);
    #print STDERR "field=$field, vals=@vals\n";
    push @commonFields, [$field => $_] foreach @vals;
  }

  my @aclFields = $indexer->getAclFields($web, $topic, $meta);
  push @commonFields, @aclFields if @aclFields;

  foreach my $key ($this->getKnownMetaData) {
    next unless $meta->find($key);
    $this->solrIndexMetaData($indexer, $web, $topic, $meta, $key, \@commonFields);
  }
}

##############################################################################
sub solrIndexMetaData {
  my ($this, $indexer, $web, $topic, $meta, $key, $commonFields) = @_;

  # delete all previous keys of this topic
  my $metaDataDef = $Foswiki::Meta::VALIDATE{$key};
  my ($formWeb, $formTopic) = $this->getFormOfMetaData($key);

  my $formName = "$formWeb.$formTopic";
  my $topicType = $formTopic;
  $topicType =~ s/Form$//;
  #print STDERR "metaData key=$key, topicType=$topicType, formWeb=$formWeb, formTopic=$formTopic\n";

  $indexer->deleteByQuery("type:metadata form:$formName web:$web topic:$topic");

  my $formDef;
  try {
    $formDef = new Foswiki::Form($this->{session}, $formWeb, $formTopic);
  }
  catch Error with {
    #print STDERR "ERROR: MetaDataPlugin::Core::solrIndexMetaData() failed for $formWeb.$formTopic: ".shift."\n";
  };
  return unless defined $formDef;

  my @aclFields = $indexer->getAclFields($web, $topic, $meta);
  my %formFields = map { $_->{name} => $_ } @{$formDef->getFields()};
  my $nameField = new Foswiki::Form::Label(
    session => $this->{session},
    name => 'name',
    type => 'label',
    title => '#',
    attributes => 'h',
    description => '',
  );
  $formFields{name} = $nameField;

  my $url = $indexer->getScriptUrlPath($web, $topic, 'view');    # TODO: let's have an url to display one metadata record
  my $contentLanguage = $indexer->getContentLanguage($web, $topic);
  my $webtopic = "$web.$topic";
  $webtopic =~ s/\//./g;

  foreach my $record ($meta->find($key)) {

    $indexer->log("Indexing $topicType $record->{name} at $web.$topic");

    # create a solr doc for each record
    my $doc = $indexer->newDocument();

    $doc->add_fields(
      'id' => $webtopic . '#' . $key . '#' . $record->{name},
      'type' => 'metadata',
      'form' => $formName,
      'icon' => 'fa-database',
      'name' => $record->{name},
      'web' => $web,
      'topic' => $topic,
      'webtopic' => $webtopic,
      'url' => $url,

      'container_id' => $web . '.' . $topic,
      'container_web' => $web,
      'container_topic' => $topic,
      'container_url' => Foswiki::Func::getViewUrl($web, $topic),
      'container_title' => Foswiki::Func::getTopicTitle($web, $topic, undef, $meta),

      'field_TopicType_lst' => $topicType,
    );

    # add extra fields, i.e. ACLs
    $doc->add_fields(@$commonFields) if $commonFields && @$commonFields;

    # loop over all fields of the record
    my $foundTitle = 0;
    my $foundText = 0;
    my @texts = ();
    foreach my $fieldName (keys %$record) {

      my $fieldValue = $record->{$fieldName} // '';
      my $fieldDef = $formFields{$fieldName};
      my $fieldType = $fieldDef->{type} // '';
      $fieldDef->{name} //= $fieldName;

      next if $fieldName eq 'name';

      # gather all text
      push @texts, $fieldValue if $fieldValue ne "" && $fieldType eq "text";

      #print STDERR "fieldName=$fieldName, fieldValue=$fieldValue\n";

      # collect some standard fields
      if ($fieldName eq 'date') {
        $fieldValue = Foswiki::Time::formatTime($fieldValue, '$iso', 'gmtime');
        $doc->add_fields("date" => $fieldValue);
        next;
      }

      if ($fieldName eq 'createdate') {
        $fieldValue = Foswiki::Time::formatTime($fieldValue, '$iso', 'gmtime');
        $doc->add_fields("createdate" => $fieldValue);
        next;
      }

      if ($fieldName eq 'author') {
        $fieldValue = Foswiki::Func::getWikiName($fieldValue || 'unknown');
        $doc->add_fields(
            "author" => $fieldValue,
            "author_title" => Foswiki::Func::getTopicTitle($Foswiki::cfg{UsersWebName}, $fieldValue),
        );
        next;
      }

      if ($fieldName eq 'createauthor') {
        $fieldValue = Foswiki::Func::getWikiName($fieldValue || 'unknown');
        $doc->add_fields(
            "createauthor" => $fieldValue,
            "createauthor_title" => Foswiki::Func::getTopicTitle($Foswiki::cfg{UsersWebName}, $fieldValue),
        );
        next;
      }

      if ($fieldName eq "Title" && $fieldValue ne "") {
        $doc->add_fields("title", $fieldValue);
        $foundTitle = 1;
        next;
      } 

      if ($fieldName eq "Summary" && $fieldType eq 'text') {
        $doc->add_fields("summary", $fieldValue) if $fieldValue ne "";
        next;
      } 

      if ($fieldName eq "Text" && $fieldType eq 'text' && $fieldValue ne "") {
        $doc->add_fields("text", $fieldValue);
        if (defined $contentLanguage && $contentLanguage ne 'detect') {
          $doc->add_fields(
            language => $contentLanguage,
            'text_' . $contentLanguage => $fieldValue,
          );
        }
        $foundText = 1;
        next;
      }


      $indexer->indexFormField($web, $topic, $fieldDef, $fieldValue, $doc) if $fieldDef;
    }

    # create an artificial title if not present explicitly
    unless ($foundTitle) {
      my $index = $record->{name};
      $index =~ s/^id//;
      $doc->add_fields("title", "$topicType $index");
    }

    # create a text if not present explicitly
    unless ($foundText) {
      $doc->add_fields("text", join(" ", @texts)) if scalar(@texts);
    }


    # add the document to the index
    try {
      $indexer->add($doc);
    }
    catch Error::Simple with {
      my $e = shift;
      $indexer->log("ERROR: " . $e->{-text});
    };
  }
}

1;
