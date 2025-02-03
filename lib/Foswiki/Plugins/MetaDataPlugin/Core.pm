# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# MetaDataPlugin is Copyright (C) 2011-2025 Michael Daum http://michaeldaumconsulting.com
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
use Foswiki::Form::Date2 ();
use Foswiki::Form::Text ();
use Foswiki::Form::User ();
use Foswiki::Plugins::JQueryPlugin ();
use Foswiki::Plugins::MetaDataPlugin ();
use Foswiki::Contrib::JsonRpcContrib::Error ();
use JSON ();
use Error qw( :try );

use constant TRACE => 0; # toggle me
#use Data::Dump qw(dump); # only for debugging

# SMELL: duplicates Foswiki::Form::reservedFieldNames
my %reservedFieldNames = map { $_ => 1 }
  qw( action breaklock contenttype cover dontnotify editaction
  forcenewrevision formtemplate onlynewtopic onlywikiname
  originalrev skin templatetopic text topic topicparent user );

##############################################################################
sub _writeDebug {
  return unless TRACE;
  print STDERR "MetaDataPlugin::Core - $_[0]\n";
  #Foswiki::Func::writeDebug("MetaDataPlugin::Core - $_[0]") if TRACE;
}

##############################################################################
sub new {
  my ($class, $session) = @_;

  $session ||= $Foswiki::Plugins::SESSION;

  #_writeDebug("called new()");

  my $this = bless({
    session => $session,
  }, $class);

  #_writeDebug("done new()");

  return $this;
}

##############################################################################
sub finish {
  my $this = shift;

  undef $this->{_topicObjs};
  undef $this->{_queryParser};
  undef $this->{_mapping};
  undef $this->{_knownMetaData};
  undef $this->{_json};
}

##############################################################################
sub json {
  my $this = shift;

  unless (defined $this->{_json}) {
    $this->{_json} = JSON->new->pretty(1)->convert_blessed(1);
  }

  return $this->{_json};
}

##############################################################################
sub paramsToJson {
  my ($this, $params) = @_;

  my %res = ();
  while (my ($k, $v) = each %$params) {
    $k = "key" if $k eq '_DEFAULT';
    next if $k =~ /^_/;
    next unless $k =~ /^[a-z0-9A-Z_]+$/;
    $res{$k} = $v;
  }

  return $this->json->encode(\%res);
}

##############################################################################
sub getQueryParser {
  my $this = shift;

  #_writeDebug("called getQueryParser()");

  unless (defined $this->{_queryParser}) {
    require Foswiki::Query::Parser;
    $this->{_queryParser} = Foswiki::Query::Parser->new();
  }

  #_writeDebug("done getQueryParser()");
  return $this->{_queryParser};
}

##############################################################################
sub registerDeleteHandler {
  my ($this, $function, $options) = @_;

  #_writeDebug("called registerDeleteHandler()");

  push @{$this->{deleteHandler}}, {
    function => $function,
    options => $options,
  };

  #_writeDebug("done registerDeleteHandler()");
}

##############################################################################
sub registerSaveHandler {
  my ($this, $function, $options) = @_;

  #_writeDebug("called registerSaveHandler()");

  push @{$this->{saveHandler}}, {
    function => $function,
    options => $options,
  };

  #_writeDebug("done registerSaveHandler()");
}

##############################################################################
sub EXPORTMETADATA {
  my ($this, $params) = @_;

  Foswiki::Plugins::JQueryPlugin::createPlugin("metadataplugin");

  my $theFormat = $params->{format};
  $theFormat = Foswiki::Func::expandTemplate("metadata::export") unless defined $theFormat;

  my $theTitle = $params->{title} // '%MAKETEXT{"Export"}%';
  my $theIcon = $params->{icon} // 'fa-download';
  my $theAttachment = $params->{attachment} // '';

  my $theMetaData = $params->{_DEFAULT} // $params->{metadata};
  return _inlineError("no metadata parameter specified") unless defined $theMetaData;

  my $theTopic = $params->{topic} || $this->{session}{webName}.'.'.$this->{session}{topicName};
  my ($web, $topic) = Foswiki::Func::normalizeWebTopicName(undef, $theTopic);
  return _inlineError("topic $theTopic does not exist") unless Foswiki::Func::topicExists($web, $topic);

  my $theClass = $params->{class} // '';
  my $theAlign = $params->{align} // '';
  
  $theFormat =~ s/\$title/$theTitle/g;
  $theFormat =~ s/\$icon/$theIcon/g;
  $theFormat =~ s/\$meta/$theMetaData/g;
  $theFormat =~ s/\$web/$web/g;
  $theFormat =~ s/\$topic/$topic/g;
  $theFormat =~ s/\$class/$theClass/g;
  $theFormat =~ s/\$align/$theAlign/g;
  $theFormat =~ s/\$attachment/$theAttachment/g;

  return $theFormat;
}

##############################################################################
sub IMPORTMETADATA {
  my ($this, $params) = @_;

  Foswiki::Plugins::JQueryPlugin::createPlugin("metadataplugin");

  my $theFormat = $params->{format};
  $theFormat = Foswiki::Func::expandTemplate("metadata::import") unless defined $theFormat;

  my $theTitle = $params->{title} // '%MAKETEXT{"Import"}%';
  my $theIcon = $params->{icon} // 'fa-upload';

  my $theMetaData = $params->{_DEFAULT} // $params->{metadata};
  return _inlineError("no metadata parameter specified") unless defined $theMetaData;

  my $theUnique = $params->{unique};
  return _inlineError("no unique parameter specified") unless defined $theUnique;

  my $theAttachment = $params->{attachment};
  return _inlineError("no attachment parameter specified") unless defined $theAttachment;

  my $theTopic = $params->{topic} || $this->{session}{webName}.'.'.$this->{session}{topicName};
  my ($web, $topic) = Foswiki::Func::normalizeWebTopicName(undef, $theTopic);
  return _inlineError("topic $theTopic does not exist") unless Foswiki::Func::topicExists($web, $topic);

  my $theClass = $params->{class} // '';
  my $theAlign = $params->{align} // '';
  
  $theFormat =~ s/\$title/$theTitle/g;
  $theFormat =~ s/\$icon/$theIcon/g;
  $theFormat =~ s/\$meta/$theMetaData/g;
  $theFormat =~ s/\$web/$web/g;
  $theFormat =~ s/\$topic/$topic/g;
  $theFormat =~ s/\$unique/$theUnique/g;
  $theFormat =~ s/\$attachment/$theAttachment/g;
  $theFormat =~ s/\$class/$theClass/g;
  $theFormat =~ s/\$align/$theAlign/g;

  return $theFormat;
}

##############################################################################
sub NEWMETADATA {
  my ($this, $params) = @_;

  #_writeDebug("called NEWMETADATA()");
  Foswiki::Plugins::JQueryPlugin::createPlugin("metadataplugin");

  my $theMetaData = lc($params->{_DEFAULT} || $params->{meta} // '');
  my $theWarn = Foswiki::Func::isTrue($params->{warn}, 0);
  my $theTitle = $params->{title};
  my $theButtonTitle = $params->{buttontitle};
  my $theFormat = $params->{format};
  my $theTemplate = $params->{template} || 'metadata::new';
  my $theTopic = $params->{topic} || $this->{session}{webName}.'.'.$this->{session}{topicName};
  my $theMap = $params->{map} // '';
  my $theIcon = $params->{icon} || 'fa-plus';
  my $theIncludeAttr = $params->{includeattr} // '';
  my $theExcludeAttr = $params->{excludeattr} // '';
  my $theClass = $params->{class} // '';

  my ($web, $topic) = Foswiki::Func::normalizeWebTopicName($this->{session}{webName}, $theTopic);
  $theTopic = "$web.$topic";

  my $metaDataDef = $this->getMetaDataDef($web, $theMetaData);
  return ($theWarn?_inlineError("can't find meta data definition for $theMetaData"):'') unless defined $metaDataDef;

  foreach my $map (split(/\s*,\s*/, $theMap)) {
    $map =~ s/^\s+//;
    $map =~ s/\s+$//;
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

  my $wikiName = Foswiki::Func::getWikiName();

  return ($theWarn?_inlineError("Error: access denied to change $web.$topic"):'')
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
  $theFormat =~ s/%class%/$theClass/g;

  #_writeDebug("done NEWMETADATA()");
  
  return $theFormat;
}

##############################################################################
sub RENDERMETADATA {
  my ($this, $params) = @_;

  _writeDebug("called RENDERMETADATA()");
  Foswiki::Plugins::JQueryPlugin::createPlugin("metadataplugin");

  my $request = Foswiki::Func::getRequestObject();
  my $metaData = lc($params->{key} || $params->{_DEFAULT} || '');
  my $topic = $params->{topic} || $this->{session}{topicName};
  my $web = $params->{web} || $this->{session}{webName};
  my $warn = Foswiki::Func::isTrue($params->{warn}, 1);
  my $rev = $params->{revision} || $request->param("rev");
  my $doLocking = Foswiki::Func::isTrue($params->{locking}, 1);

  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);
  $params->{web} = $web;
  $params->{topic} = $topic;

  my $action = $params->{action} || 'view';
  my $wikiName = Foswiki::Func::getWikiName();

  my $topicObj = getTopicObject($this, $web, $topic, $rev); 

  $params->{_gotViewAccess} = Foswiki::Func::checkAccessPermission("VIEW", $wikiName, undef, $topic, $web, $topicObj);
  $params->{_gotWriteAccess} = Foswiki::Func::checkAccessPermission("CHANGE", $wikiName, undef, $topic, $web, $topicObj);
  $params->{_lockedBy} = '';
  (undef, $params->{_lockedBy}) = Foswiki::Func::checkTopicEditLock($web, $topic) if $doLocking;  

  $params->{_lockedBy} = Foswiki::Func::getWikiName($params->{_lockedBy})
    if $params->{_lockedBy};

  my $currentWikiName = Foswiki::Func::getWikiName();
  $params->{_isLocked} = ($params->{_lockedBy} ne '' && $params->{_lockedBy} ne $currentWikiName)?1:0;

  _writeDebug("currentWikiName=$currentWikiName, lockedBy=$params->{_lockedBy}, isLocked=$params->{_isLocked}");

  return ($warn?_inlineError("%MAKETEXT{\"Warning: this topic is locked by user [_1].\" args=\"$params->{_lockedBy}\"}%"):'')
    if $action eq 'edit' && $params->{_isLocked};

  return ($warn?_inlineError("Error: access denied to view $web.$topic"):'') 
    if $action eq 'view' && ! $params->{_gotViewAccess};

  return ($warn?_inlineError("Error: access denied to change $web.$topic"):'') 
    if $action eq 'edit' && ! $params->{_gotWriteAccess};

  return ($warn?_inlineError("Error: unknown action '$action'"):'') unless $action =~ /^(view|edit)$/;

  Foswiki::Func::setTopicEditLock($web, $topic, 1)
    if $action eq 'edit' && $doLocking;

  my $result = '';
  if ($metaData) {
    $result = $this->renderMetaData($topicObj, $params, $metaData);
  } else {
    foreach my $metaData ($this->getKnownMetaData($web)) {
      next unless $topicObj->find($metaData);
      $result .= $this->renderMetaData($topicObj, $params, $metaData);
    }
  }

  return $result;
}

##############################################################################
sub renderMetaData {
  my ($this, $topicObj, $params, $metaData) = @_;

  $metaData = lc($metaData);

  _writeDebug("called renderMetaData($metaData)");

  my $request = Foswiki::Func::getRequestObject();

  my $theAction = $params->{action} || 'view';
  my $theFields = $params->{field} || $params->{fields};
  my $theShowIndex = Foswiki::Func::isTrue($params->{showindex});
  my $theShowChanged = Foswiki::Func::isTrue($params->{showchanged});
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
  my $theEnabledActions = $params->{enabledactions};
  $theEnabledActions = 'edit,view,delete' unless defined $theEnabledActions;
  $theEnabledActions =~ s/^\s+|\s+$//g;
  my %enabledActions = map {lc($_) => 1} split(/\s*,\s*/, $theEnabledActions);
  my $theLimit = $params->{limit} || 0;
  my $theSkip = $params->{skip} || 0;
  my $theNavigation = Foswiki::Func::isTrue($params->{navigation}, 1);
  my $theDateFormat = $params->{"dateformat"} || $Foswiki::cfg{DateManipPlugin}{DefaultDateTimeFormat} || '$day $mon $year - $hour:$min';

  foreach my $map (split(/\s*,\s*/, $theMap)) {
    $map =~ s/^\s+//;
    $map =~ s/\s+$//;
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
      $error = $theWarn?_inlineError("Error: " . shift):'';
    };
    return $error if defined $error;
  }


  $theSort = 'name' unless defined $theSort;
  $theSort = '' if $theSort eq 'off';

  my ($formWeb, $formTopic) = $this->getFormOfMetaData($topicObj->web(), $metaData);
  return ($theWarn?_inlineError("can't find meta data definition for $metaData"):'') unless defined $formWeb;
  
  my $wikiName = Foswiki::Func::getWikiName();
  return ($theWarn?_inlineError("access denied to form definition for <nop>$metaData"):'')
    unless Foswiki::Func::checkAccessPermission("VIEW", $wikiName, undef, $formTopic, $formWeb);

  return ($theWarn?_inlineError("form definition for <nop>$metaData not found"):'')
    unless Foswiki::Func::topicExists($formWeb, $formTopic);

  my $formDef;
  try {
    $formDef = Foswiki::Form->new($this->{session}, $formWeb, $formTopic);
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
  
  return ($theWarn?_inlineError("can't parse form definition at $formWeb.$formTopic"):'')
    unless defined $formDef;

  my @selectedFields = ();
  if ($theFields) {
    foreach my $fieldName (split(/\s*,\s*/, $theFields)) {
      $fieldName =~ s/^\s+//;
      $fieldName =~ s/\s+$//;
      $fieldName .= "_" if $reservedFieldNames{$fieldName};
      my $field = $formDef->getField($fieldName);
      unless ($field) {
        if ($fieldName eq 'index') {
          $field = Foswiki::Form::Label->new(
            session    => $this->{session},
            name       => 'index',
            type       => 'label',
            title      => '#',
            description => '',
          );
        }  elsif ($fieldName eq 'name') {
          $field = Foswiki::Form::Label->new(
            session    => $this->{session},
            name       => 'name',
            type       => 'label',
            title      => '#',
            attributes => 'h',
            description => '',
          );
        }  elsif ($fieldName =~ /^(create)?date$/) {
          $field = Foswiki::Form::Date2->new(
            session    => $this->{session},
            name       => $fieldName,
            title       => $fieldName,
            type       => 'date2',
            description => '',
            value      => "format=\"$theDateFormat\"",
          );
        }  elsif ($fieldName =~ /^(create)?author$/) {
          $field = Foswiki::Form::User->new(
            session    => $this->{session},
            name       => $fieldName,
            title       => $fieldName,
            type       => 'text',
            description => '',
          );
        }
      }
      push @selectedFields, $field if $field;
    }
  } else {
    if ($theShowIndex) {
      my $indexField = Foswiki::Form::Label->new(
        session    => $this->{session},
        name       => 'index',
        type       => 'label',
        title      => '#',
        description => '',
      );
      push @selectedFields, $indexField;
    }
    my $nameField = Foswiki::Form::Label->new(
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
    if ($theShowChanged) {
      my $dateField = Foswiki::Form::Date2->new(
        session    => $this->{session},
        name       => 'date',
        type       => 'date2',
        title      => 'Changed',
        description => '',
        value => "format=\"<span style='display:none'> \$epoch </span><nobr>$theDateFormat</nobr>\""
      );
      push @selectedFields, $dateField;
    }
  }

  my $name = $params->{name};

  # default formats
  $theMandatory = " <span class='foswikiAlert'>**</span> " unless defined $theMandatory;

  unless (defined $theHeader) {
    if ($theAction eq 'view') {
      if (defined $name) { # single mode
        $theHeader = '<div class="foswikiPageForm">$n<table class="foswikiLayoutTable $class"><tbody>$n';
      } else {
        $theHeader = '<div class="metaDataView'.($params->{_gotWriteAccess}?'':' metaDataReadOnly').'" data-metadata="'.$metaData.'" data-rev="$revision">$n'.
            '%params%'.
            '<table class="foswikiTable $class"><thead><tr><th>$n'.join(' </th><th>$n', 
          map {
            my $title = $_->{title}; 
            my $name = $_->{name}; 
            defined($params->{$name.'_title'})?$params->{$name.'_title'}:$title
          } 
          grep {$_->{name} ne 'name'}
          @selectedFields).' </th></tr></thead><tbody>$n';
      }
    } else {
      $theHeader = '<div class="metaDataEdit foswikiFormSteps">$n';
    }
  }
  $theHeader =~ s/\%params\%/<script type="application\/json" class="metaDataParams"><literal>\$params<\/literal><\/script>\$n/;

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
        $theFormat = '<tr class="metaDataRow"><td>$n'.join(' </td><td>$n', 
          map {
            '$'.$_->{name}
          } 
          grep {$_->{name} ne 'name'}
          @selectedFields).' '.($params->{_gotWriteAccess}?'$actions':'').'$n</td></tr>$n';
      }
    } else {
      $theFormat = '<div class="foswikiFormStep $metadata">$n<table class="foswikiLayoutTable">$n'.
        join('$n', map {'$'.$_->{name}} @selectedFields).
        '$n</table></div>';
    }
  }

  unless (defined $theFieldFormat) {
    if ($theAction eq 'view') {
      if (defined $name) { # single mode
        $theFieldFormat = '<tr><th valign="top">$title:</th><td>$value</td></tr>';
      } else {
        $theFieldFormat = '$value';
      }
    } else {
      $theFieldFormat = '  <tr class="$metadata $name">$n'.
        '    <th valign="top">$title:$mandatory</th>$n'.
        '    <td>$n$edit$n<div class="foswikiFormDescription">$description</div></td>'.
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
      $record = $this->createRecord();
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

      $fieldName =~ s/_$//;
      my $metaFieldName = 'META:'.$metaDataKey.':'.$name.':'.$fieldName; 

      if ($theAction eq 'edit') {
        $field->{name} = $metaFieldName; 
      }

      my $fieldAllowedValues = '';
      # CAUTION: don't use field->getOptions() on a +values field as that won't return the full valueMap...only the value part, but not the title map
      if ($field->can('getOptions') && !isValueMapped($field)) {
        #_writeDebug("can getOptions");
        my $options = $field->getOptions();
        if ($options) {
          #_writeDebug("options=$options");
          $fieldAllowedValues = join($theValueSep, @$options);
        }
      } else {
        #_writeDebug("can't getOptions ... fallback to field->{value}");
        # fallback to field->value
        my $options = $field->{value};
        if ($options) {
          $fieldAllowedValues = join($theValueSep, split(/\s*,\s*/, $options));
        }
      }
      #_writeDebug("fieldAllowedValues=$fieldAllowedValues");

      # get the list of all allowed values without any +values mapping applied
      my $fieldOrigAllowedValues = '';
      if ($field->can('getOptions')) {
        #_writeDebug("can getOptions");
        my $options = $field->getOptions();
        if ($options) {
          #_writeDebug("options=$options");
          $fieldOrigAllowedValues = join($theValueSep, @$options);
        }
      } else {
        #_writeDebug("can't getOptions ... fallback to field->{value}");
        # fallback to field->value
        my $options = $field->{value};
        if ($options) {
          $fieldOrigAllowedValues = join($theValueSep, split(/\s*,\s*/, $options));
        }
      }
      #_writeDebug("fieldOrigAllowedValues=$fieldOrigAllowedValues");

      # get the default value
      my $fieldDefault = '';
      if ($field->can('getDefaultValue')) {
        $fieldDefault = $field->getDefaultValue() // '';
      } 

      my $fieldValue = $this->getFieldValue($record, $fieldName);
      $fieldValue = $index if !defined($fieldValue) && $fieldName eq 'index';

      if ($fieldName =~ /^(create)?date$/) {
        $fieldValue ||= 0;
        #$fieldValue = Foswiki::Func::formatTime($fieldValue, $theDateFormat);
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

      my $fieldMandatory = Foswiki::Func::isTrue($params->{$fieldName."_mandatory"}, $field->isMandatory) ? $theMandatory:'';
      $fieldAttrs .= ", M" if $fieldMandatory;

      if ($theAction eq 'edit') { # or get value from url (highest prio)
        my $urlValue;
        my $key = 'META_'.uc($metaData).'_'.$fieldName;
        if ($field->isMultiValued) {
          my @urlValue = $request->multi_param($key);
          $urlValue = join(", ", @urlValue) if @urlValue;
        } else {
          $urlValue = $request->param($key);
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

      $fieldValue = $fieldDefault unless defined $fieldValue && $fieldValue ne "";
      $fieldDescription //= '';
      #_writeDebug("metaData=$metaData, fieldName=$fieldName, fieldValue=$fieldValue");

      if ($theHideEmpty && $theAction eq 'view' && (!defined($fieldValue) || $fieldValue eq '')) {
        $row =~ s/\$$fieldName//g;
        next;
      }

      # temporarily remap field to another type
      my $tmpField;
      if (defined($params->{$fieldName.'_type'}) || 
          defined($params->{$fieldName.'_size'}) ||
          defined($params->{$fieldName.'_mandatory'}) ||
          $fieldSort) {
        $tmpField = $field;
        $field = $formDef->createField(
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
        }, $topicObj); # SMELL what about the attrs param in Foswiki::Form; wtf is this attr anyway
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

      $row =~ s/\$$fieldName[\b_]/$line/g;
      $row =~ s/\$orig$fieldName[\b_]/$fieldValue/g;

      $fieldValues{$fieldName} = {
        value => $line,
        orig => $fieldValue,
      };

      #_writeDebug("line=$line");
      push @fieldResult, $line;

      # cleanup
      if (defined $tmpField) {
        $field->finish();
        $field = $tmpField;
      }

      $field->{name} = $fieldName;
    }
    
    #_writeDebug("row='$row'");

    $title = $name unless $title;

    my $fieldActions = '';

    if ($params->{_gotWriteAccess}) {
      $fieldActions = Foswiki::Func::expandTemplate("metadata::actions");

      my $fieldEditAction = $enabledActions{edit}?Foswiki::Func::expandTemplate("metadata::action::edit"):"";
      my $fieldViewAction = $enabledActions{view}?Foswiki::Func::expandTemplate("metadata::action::view"):"";
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
      $fieldActions =~ s/\%view\%/$fieldViewAction/g;
      $fieldActions =~ s/\%duplicate\%/$fieldDuplicateAction/g;
      $fieldActions =~ s/\%delete\%/$fieldDeleteAction/g;
      $fieldActions =~ s/\%move\%/$fieldMoveAction/g;
      $fieldActions =~ s/\%title\%/$title/g;
      $fieldActions =~ s/\%name\%/$name/g;
      $fieldActions =~ s/\%meta\%/$metaData/g;
      $fieldActions =~ s/\%topic\%/$topic/g;
      $fieldActions =~ s/\%map\%/$theMap/g;
      $fieldActions =~ s/\%id\%/$id/g;
      $fieldActions =~ s/\%navigation\%/$navigation/g;
      $fieldActions =~ s/%includeattr%/$theIncludeAttr/g;
      $fieldActions =~ s/%excludeattr%/$theExcludeAttr/g;
    }

    my $fieldResult = '';
    $fieldResult = $theFieldHeader.join($theFieldSep, @fieldResult).$theFieldFooter if @fieldResult;

    $row =~ s/\$actions\b/$fieldActions/g;

    foreach my $fieldName (keys %fieldValues) {
      $row =~ s/\$$fieldName\b/$fieldValues{$fieldName}{value}/g;
      $row =~ s/\$orig$fieldName\b/$fieldValues{$fieldName}{orig}/g;
    }

    $row =~ s/\$index\b/$index/g;
    $row =~ s/\$id\b/$name/g;
    $row =~ s/\$date\b/Foswiki::Func::formatTime($record->{date}, $theDateFormat)/ge;
    $row =~ s/\$datetime\b/$record->{date}/g;
    $row =~ s/\$createdate\b/$record->{createdate}/g;
    $row =~ s/\$fields\b/$fieldResult/g;
    $row =~ s/\$formatTime\((.*?)(?:,\s*'([^']*?)')?\)/Foswiki::Func::formatTime($1, $2 || $theDateFormat)/ge;

    push @result, $row unless $theHideEmpty && $row eq '';
    last if $theLimit && scalar(@result) >= $theLimit;
  }

  return '' if $theHideEmpty && !@result;

  my $theClass = $params->{class} // '';
  my $result = $theHeader.join($theSep, @result).$theFooter;

  my $formTitle = Foswiki::Func::getTopicTitle($formWeb, $formTopic);
  my $topicInfo = $topicObj->getRevisionInfo();

  # parse out verbatim areas
  my $verbatim = {};

  my $foundVerbatim = 0;
  if ($result =~ /&lt;\/?verbatim&gt;/g) {
    $result =~ s/&lt;verbatim&gt;/<verbatim>/g;
    $result =~ s/&lt;\/verbatim&gt;/<\/verbatim>/g;
    $foundVerbatim = 1;
  }
  $result = Foswiki::takeOutBlocks($result, 'verbatim', $verbatim); # SMELL: we have to do this _again_ by _ourselves as any other callback doesn't cut it

  $result =~ s/\$class\b/$theClass/g;
  $result =~ s/\$count\b/$index/g;
  $result =~ s/\$revision\b/$topicInfo->{version}/g; # the meta data name
  $result =~ s/\$metadata\b/$metaData/g; # the meta data name
  $result =~ s/\$form\b/$formWeb.$formTopic/g; # the meta data definition
  $result =~ s/\$formtitle\b/$formTitle/g; # the meta data definition title
  $result =~ s/\$nop//g;
  $result =~ s/\$n/\n/g;
  $result =~ s/\$perce?nt/%/g;
  $result =~ s/\$dollar/\$/g;
  $result =~ s/\$lockedby\b/$params->{_lockedBy}/g;
  $result =~ s/\$islocked\b/$params->{_isLocked}/g;

  my $paramString = $this->paramsToJson($params);
  $result =~ s/\$params\b/$paramString/g;

  Foswiki::putBackBlocks(\$result, $verbatim, 'verbatim');
  if ($foundVerbatim) {
    $result =~ s/<verbatim>/&lt;verbatim&gt;/g;
    $result =~ s/<\/verbatim>/&lt;\/verbatim&gt;/g;
  }

  #_writeDebug("done renderMetaData()");
  return $result;
}

##############################################################################
sub getTopicObject {
  my ($this, $web, $topic, $rev) = @_;

  #_writeDebug("called getTopicObject()");

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

  #_writeDebug("done getTopicObject()");
  return $topicObj;
}

##############################################################################
sub createRecord {
  my $this = shift;

  return {
    name => 'id',
    date => time(),
    author => Foswiki::Func::getCanonicalUserID(),
    createdate => time(),
    createauthor => Foswiki::Func::getCanonicalUserID(),
  };
}

##############################################################################
sub getKnownMetaData {
  my ($this, $web) = @_;

  $web //= $this->{session}{webName};
  $web =~ s/\//\./g;

  _writeDebug("called getKnownMetaData($web)");
  Foswiki::Plugins::MetaDataPlugin::registerMetaData($web);

  unless (defined $this->{_knownMetaData}{$web}) {
    $this->{_knownMetaData}{$web} = [];
    foreach my $name (sort keys %Foswiki::Meta::VALIDATE) {

      # some well known meta data that is not of interest here
      next if $name =~ /^(TOPICINFO|TOPICMOVED|FIELD|FORM|FILEATTACHMENT|TOPICPARENT|PREFERENCE)$/; 

      # test if a form definitio exists
      my ($formWeb, $formTopic) = $this->getFormOfMetaData($web, $name);
      if ($formWeb && $formTopic && Foswiki::Func::topicExists($formWeb, $formTopic)) {
        push @{$this->{_knownMetaData}{$web}}, $name;
      }
    }
  };

  #_writeDebug("done getKnownMetaData()");
  return @{$this->{_knownMetaData}{$web}};
}

##############################################################################
sub getFormDef {
  my ($this, $web, $key) = @_;

  _writeDebug("called getFormDef($web, $key)");

  my ($formWeb, $formTopic) = $this->getFormOfMetaData($web, $key);
  return unless defined $formWeb && defined $formTopic;
  
  my $formDef;
  try {
    $formDef = Foswiki::Form->new($this->{session}, $formWeb, $formTopic);
  }
  catch Error with {
    #print STDERR "ERROR: MetaDataPlugin::Core::getFormDef() failed for $formWeb.$formTopic: ".shift."\n";
  };

  return $formDef;
}

##############################################################################
sub getMetaDataDef {
  my ($this, $web, $key) = @_;

  Foswiki::Plugins::MetaDataPlugin::registerMetaData($web);
  return $Foswiki::Meta::VALIDATE{uc($key)};
}

##############################################################################
sub getFormOfMetaData {
  my ($this, $web, $key) = @_;

  _writeDebug("getFormOfMetaData($web, $key)");
  my $metaDataDef = $this->getMetaDataDef($web, $key);
  return unless defined $metaDataDef;

  my $formWeb = $web;
  my $formTopic = $metaDataDef->{form};

  $formTopic = $Foswiki::cfg{SystemWebName}.'.'.ucfirst(lc($key)).'Form' 
    unless defined $formTopic;

  ($formWeb, $formTopic) = Foswiki::Func::normalizeWebTopicName($formWeb, $formTopic);

  _writeDebug("...form=$formWeb.$formTopic");

  return ($formWeb, $formTopic);
}

##############################################################################
sub beforeSaveHandler {
  my ($this, $text, $topic, $web, $meta) = @_;

  #_writeDebug("called beforeSaveHandler($web.$topic)");

  my $request = Foswiki::Func::getRequestObject();
  my %records = ();

  my $knownMetaDataPattern = join('|', $this->getKnownMetaData($web));
  #_writeDebug("knownMetaDataPattern=$knownMetaDataPattern");

  my $cUID = Foswiki::Func::getCanonicalUserID();
  my $action = $request->param("action") // "save";

  my $explicitName;
  foreach my $urlParam ($request->param()) {
    unless ($urlParam =~ /^META:($knownMetaDataPattern):(id\d*):(.+)$/) {
      #_writeDebug("urlParam does not match: $urlParam");
      next;
    }
    #_writeDebug("got urlParam=$urlParam"); 
    my $metaDataName = $1;
    my $name = $2;
    my $field = $3;

    $name = "id" if $action eq "copy";

    _writeDebug("metaDataName=$metaDataName, name=$name, $field=$field"); 
    #print STDERR "urlParam=$urlParam, metaDataName=$metaDataName, name=$name field=$field\n";

    # look up cache
    my $record = $records{$metaDataName.':'.$name};

    # first hit
    unless (defined $record) {
    
      if ($name eq 'id') {
        # a new one 
        $record = $this->createRecord();
      } else {
        # go fetch from store
        $record = $meta->get($metaDataName, $name);
      }
    }

    my $value;

    #_writeDebug("$urlParam=$value");

    # when duplicating a field, the name parameter will have a dummy 'id'
    # to flag that we need to create a new record based on the give one
    # SMELL: doesn't work
    if ($field eq 'name') {
      $value = $request->param($urlParam) || 'id';
      $value = 'id'.($this->getMaxId($metaDataName, $meta)+1) if $value eq 'id';
    } else {
      my $formDef = $this->getFormDef($web, $metaDataName);
      my $fieldDef;
      $fieldDef = $formDef->getField($field) if $formDef;
      if ($fieldDef) {
        if ($fieldDef->isMultiValued) {
          my $sep = $fieldDef->can("param") ? ($fieldDef->param("separator") ||", ") : ", ";
          my @value = $request->multi_param($urlParam);
          if (@value) {
            $value = join($sep, @value);
            $value =~ s/,\s*$//g;
          }
        } else {
          $value = $request->param($urlParam);
        }
        $value = '' unless defined $value;

        my $keyValues = {
          value => $value
        };
        $fieldDef->createMetaKeyValues($request, $meta, $keyValues);
        $value = $keyValues->{value};
      } else {
        #print STDERR "field $field not found\n";
      }
    }

    $record->{$field} = $value;


    $records{$metaDataName.':'.$name} = $record;

    # delete from request to prevent the record being stored twice by subsequent saveAs()
    $request->delete($urlParam);
  }

  #_writeDebug("records=".Data::Dumper->Dump([\%records]));

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

          _writeDebug("executing $function");
          try {
            no strict 'refs'; ## no critic
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

  #_writeDebug("done beforeSaveHandler($web.$topic)");
}

##############################################################################
sub getMaxId {
  my ($this, $name, $meta) = @_;

  #_writeDebug("called getMaxId()");
  my $maxId = 0;

  foreach my $record ($meta->find($name)) {
    my $id = $record->{name};
    $id =~ s/^id//;
    $maxId = $id if $id > $maxId;
  }

  #_writeDebug("getMaxId($name) = $maxId");
  #_writeDebug("done getMaxId()");

  return $maxId;
}

##############################################################################
sub jsonRpcLockTopic {
  my ($this, $request) = @_;

  my $web = $this->{session}{webName};
  my $topic = $request->param('topic') || $this->{session}{topicName};
  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  _writeDebug("called jsonRpcLockTopic($web, $topic)");

  Foswiki::Plugins::MetaDataPlugin::registerMetaData($web);

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

  _writeDebug("called jsonRpcUnlockTopic($web, $topic)");

  Foswiki::Plugins::MetaDataPlugin::registerMetaData($web);

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
sub jsonRpcGet {
  my ($this, $request) = @_;

  my $web = $this->{session}{webName};
  my $topic = $request->param('topic') || $this->{session}{topicName};
  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  _writeDebug("called jsonRpcGet($web, $topic)");

  Foswiki::Plugins::MetaDataPlugin::registerMetaData($web);

  my $rev = $request->param("revision");

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "topic not found")
    unless Foswiki::Func::topicExists($web, $topic, $rev);

  my $wikiName = Foswiki::Func::getWikiName();
  my ($meta) = Foswiki::Func::readTopic($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $wikiName, undef, $topic, $web, $meta);

  my $metaData = $request->param('metadata') // '';
  my $metaDataKey = uc($metaData);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "unknown meta")
    unless defined $this->getMetaDataDef($web, $metaDataKey);

  my $name = $request->param('name');

  my ($formWeb, $formTopic) = $this->getFormOfMetaData($web, $metaData);
  throw Foswiki::Contrib::JsonRpcContrib::Error("1002", "can't find meta data definition for $metaData")
    unless defined $formWeb && defined $formTopic;

  my $formDef = Foswiki::Form->new($this->{session}, $formWeb, $formTopic);

  # get a single record
  if (defined $name) {
    my $record = $meta->get($metaDataKey, $name);
    throw Foswiki::Contrib::JsonRpcContrib::Error(1001, "$metaData record not found")
      unless $record;
    return $record;
  }

  my %includeMap = ();
  my $filter = $request->param("filter");
  if (defined $filter) {
    my $queryParser = $this->getQueryParser();
    my $error;
    my $query = "'".$meta->getPath()."'/META:".$metaDataKey."[".$filter."].name";

    #print STDERR "query=$query\n";
  
    my $node = $queryParser->parse($query);
    my $result = $node->evaluate(tom => $meta, data => $meta);
    if (defined $result) {
      if (ref($result) ne 'ARRAY') {
        $result = [$result];
      }
      %includeMap = map {$_ => 1} @$result;
    }

    #print STDERR "includeMap=".dump(\%includeMap)."\n";
  }

  # get a list of records
  my @result = ();
  foreach my $record ($meta->find($metaDataKey)) {
    my $found = 1;

    next if defined $filter && !$includeMap{$record->{name}};

    foreach my $formField (@{$formDef->getFields()}) {
      my $key = $formField->{name};
      my $val = $record->{$key};
      my $param = $request->param($key);
      if (defined $param && defined $record->{$key} && $record->{$key} !~ /$param/i) {
        $found = 0;
        last;
      }
    }

    push @result, $record if $found;
  }

  throw Foswiki::Contrib::JsonRpcContrib::Error("1003", "nothing found")
    unless @result;

  return \@result;
}

##############################################################################
sub jsonRpcSave {
  my ($this, $request) = @_;

  my $web = $this->{session}{webName};
  my $topic = $request->param('topic') || $this->{session}{topicName};
  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  _writeDebug("called jsonRpcSave($web, $topic)");

  Foswiki::Plugins::MetaDataPlugin::registerMetaData($web);

  my $loginName;
  my $wikiName;
  (undef, $loginName) = Foswiki::Func::checkTopicEditLock($web, $topic);
  $wikiName = Foswiki::Func::getWikiName($loginName) if $loginName;

  my $currentWikiName = Foswiki::Func::getWikiName();
  throw Foswiki::Contrib::JsonRpcContrib::Error(405, "topic is locked by $wikiName") 
    if $loginName ne '' && $wikiName ne $currentWikiName;

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "topic not found") 
    unless Foswiki::Func::topicExists($web, $topic);

  my ($meta) = Foswiki::Func::readTopic($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "access denied")
    unless Foswiki::Func::checkAccessPermission("CHANGE", $currentWikiName, undef, $topic, $web, $meta);

  my $metaData = $request->param('metadata') // '';
  my $metaDataKey = uc($metaData);

  #print STDERR "known meta=".join(", ", sort keys %Foswiki::Meta::VALIDATE)."\n";
  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "unknown meta")
    unless defined $Foswiki::Meta::VALIDATE{$metaDataKey};

  my $name = $request->param('name');
  throw Foswiki::Contrib::JsonRpcContrib::Error(1003, "no name")
    unless defined $name;

  my $record;
  my $mustSave = 0;
  if ($name eq "id") {
    $record = $this->createRecord;
    $record->{name} = 'id'.($this->getMaxId($metaDataKey, $meta)+1);
    $mustSave = 1;
  } else {
    $record = $meta->get($metaDataKey, $name);
  }

  throw Foswiki::Contrib::JsonRpcContrib::Error(1001, "$metaData record not found")
    unless $record;

  my ($formWeb, $formTopic) = $this->getFormOfMetaData($web, $metaData);
  throw Foswiki::Contrib::JsonRpcContrib::Error("1002", "can't find meta data definition for $metaData")
    unless defined $formWeb && defined $formTopic;

  my $formDef = Foswiki::Form->new($this->{session}, $formWeb, $formTopic);

  # populate record from request
  foreach my $formField (@{$formDef->getFields()}) {
    my $key = $formField->{name};
    next if $key =~ /^(name|author|date|createauthor|createdate)$/; # internal props


    my $val = $request->param($key);
    next unless defined $val;

    my $oldVal = $record->{$key};
    next if defined($oldVal) && $oldVal eq $val;

    $record->{$key} = $val;
    $mustSave = 1;
  }

  # delete unknown fields
  my %knownFields = map {$_->{name} => 1} @{$formDef->getFields()};
  foreach my $key (keys %$record) {
    next if $knownFields{$key} || $key =~ /^(name|author|date|createauthor|createdate)$/;
    delete $record->{$key};
    $mustSave = 1;
  }

  if ($mustSave) {
    $meta->putKeyed($metaDataKey, $record);
    $meta->save(ignorepermissions => 1);
    return 'ok';
  }

  return 'no changes';
}

##############################################################################
sub jsonRpcDelete {
  my ($this, $request) = @_;

  my $web = $this->{session}{webName};
  my $topic = $request->param('topic') || $this->{session}{topicName};
  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  _writeDebug("called jsonRpcDelete($web, $topic)");
  Foswiki::Plugins::MetaDataPlugin::registerMetaData($web);

  my $loginName;
  my $wikiName;
  (undef, $loginName) = Foswiki::Func::checkTopicEditLock($web, $topic);
  $wikiName = Foswiki::Func::getWikiName($loginName) if $loginName;

  my $currentWikiName = Foswiki::Func::getWikiName();
  throw Foswiki::Contrib::JsonRpcContrib::Error(405, "topic is locked by $wikiName") 
    if $loginName ne '' && $wikiName ne $currentWikiName;

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "topic not found") 
    unless Foswiki::Func::topicExists($web, $topic);

  my ($meta) = Foswiki::Func::readTopic($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "access denied")
    unless Foswiki::Func::checkAccessPermission("CHANGE", $currentWikiName, undef, $topic, $web, $meta);

  my $metaData = $request->param('metadata') // '';

  my $metaDataKey = uc($metaData);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "unknown meta")
    unless defined $Foswiki::Meta::VALIDATE{$metaDataKey};

  my $name = $request->param('name') // $request->param('metadata::name') // '';
  my $record = $meta->get($metaDataKey, $name);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1001, "$metaData record not found")
    unless $record;

  #_writeDebug("$this, checking deleteHandler ... ");
  if (defined $this->{deleteHandler}) {
    foreach my $deleteHandler (@{$this->{deleteHandler}}) {
      my $function = $deleteHandler->{function};
      my $result;
      my $error;

      try {
        no strict 'refs'; ## no critic
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
  $meta->save(ignorepermissions => 1);

  #_writeDebug("done jsonRpcDelete()");

  return 'ok';
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

    if (!$isNumeric && $isDate) {
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
    $fieldValue = Foswiki::Func::expandCommonVariables($fieldValue, $meta->topic, $meta->web, $meta) 
      if $fieldValue =~ /%/;
  }

  my $mappedValue = $this->{_mapping}{$fieldValue};
  return $mappedValue if defined $mappedValue;

  return $fieldValue;
}

##############################################################################
# NOTE: this basically does the same as DBCacheContrib::_loadTopic() would do
# however we need to make sure all custom metadata definitions are loaded up to this point
# as otherwise keys wont be loaded
# UPDATE: ... which has been achieved in lateInitPlugin or initPlugin by now
#
sub DISABLED_dbcacheIndexTopicHandler {
  my ($this, $db, $obj, $web, $topic, $meta, $text) = @_;


  my $archivist = $db->getArchivist();
  foreach my $key ($this->getKnownMetaData($web)) {
    my $validation = $Foswiki::Meta::VALIDATE{$key};

    if ($validation->{many}) {
      my @records = $meta->find($key);
      next unless @records;

      my $array = $db->fastget(lc($key));
      unless (defined($array)) {
        $array = $archivist->newArray();
        $obj->set(lc($key), $array);
      }
      foreach my $record (@records) {
        my $map = $archivist->newMap(initial => $record);
        $array->add($map);
      }
    } else {
      my $record = $meta->get($key);
      next unless $record;

      my $map = $archivist->newMap(initial => $record);
      $obj->set(lc($key), $map);
    }
  }
}

##############################################################################
sub solrIndexTopicHandler {
  my ($this, $indexer, $doc, $web, $topic, $meta, $text) = @_;

  my @commonFields = ();
  for my $field (qw(tag category webcat)) {
    my @vals = $doc->values_for($field);
    #print STDERR "field=$field, vals=@vals\n";
    push @commonFields, [$field => $_] foreach @vals;
  }

  my @aclFields = $indexer->getAclFields($web, $topic, $meta);
  push @commonFields, @aclFields if @aclFields;

  foreach my $key ($this->getKnownMetaData($web)) {
    next unless $meta->find($key);
    $this->solrIndexMetaData($indexer, $web, $topic, $meta, $key, \@commonFields);
  }
}

##############################################################################
sub solrIndexMetaData {
  my ($this, $indexer, $web, $topic, $meta, $key, $commonFields) = @_;

  my $metaDataDef = $this->getMetaDataDef($web, $key);
  return if $metaDataDef->{ignoreSolrIndex};

  # delete all previous keys of this topic
  my ($formWeb, $formTopic) = $this->getFormOfMetaData($web, $key);

  my $formName = "$formWeb.$formTopic";
  my $topicType = $formTopic;
  $topicType =~ s/Form$//;
  #print STDERR "metaData key=$key, topicType=$topicType, formWeb=$formWeb, formTopic=$formTopic\n";

  #$indexer->deleteByQuery("type:metadata form:$formName web:$web topic:$topic");

  my $formDef;
  try {
    $formDef = Foswiki::Form->new($this->{session}, $formWeb, $formTopic);
  }
  catch Error with {
    #print STDERR "ERROR: MetaDataPlugin::Core::solrIndexMetaData() failed for $formWeb.$formTopic: ".shift."\n";
  };
  return unless defined $formDef;

  my @aclFields = $indexer->getAclFields($web, $topic, $meta);
  my %formFields = map { $_->{name} => $_ } @{$formDef->getFields()};
  my $nameField = Foswiki::Form::Label->new(
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
      next if $fieldName =~ /_origvalue$/;

      my $fieldValue = $record->{$fieldName} // '';
      my $fieldDef = $formFields{$fieldName};
      my $fieldType = $fieldDef->{type} // '';
      $fieldDef->{name} //= $fieldName;

      next if $fieldName eq 'name';

      # gather all text
      if ($fieldType =~ /text|natedit/ && $fieldValue ne "") {
        $fieldValue = $indexer->plainify($fieldValue);
        push @texts, $fieldValue;
      }

      #print STDERR "fieldName=$fieldName, fieldValue=$fieldValue\n";

      # collect some standard fields
      if ($fieldName =~ /^(date|createdate)$/) {
        my $date = Foswiki::Time::formatTime($fieldValue, '$iso', 'gmtime');
        my $dateStr = Foswiki::Time::formatTime($fieldValue);
        $doc->add_fields(
          $fieldName => $date,
          $fieldName."_s" => $dateStr
        );
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

      if ($fieldName eq "Text" && $fieldType =~ /text|natedit/ && $fieldValue ne "") {
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

##############################################################################
sub isValueMapped {
  my $fieldDef = shift;

  return $fieldDef ? $fieldDef->can("isValueMapped") ? $fieldDef->isValueMapped() : $fieldDef->{type} =~ /\+values/ : 0;
}

##############################################################################
sub _inlineError {
  my $msg = shift;
  return "<span class='foswikiAlert'>$msg</span>";
}


1;
