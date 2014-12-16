# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# MetaDataPlugin is Copyright (C) 2011-2014 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::MetaDataPlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Contrib::JsonRpcContrib ();
use Foswiki::Plugins::MetaDataPlugin::Core();
use Error qw( :try );

use Foswiki::Request ();

BEGIN {
  # Backwards compatibility for Foswiki 1.1.x
  unless (Foswiki::Request->can('multi_param')) {
    no warnings 'redefine';
    *Foswiki::Request::multi_param = \&Foswiki::Request::param;
    use warnings 'redefine';
  }
}

our $VERSION = '4.10';
our $RELEASE = '4.10';
our $SHORTDESCRIPTION = 'Bring custom meta data to wiki apps';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

##############################################################################
sub earlyInitPlugin {

  my $session = $Foswiki::Plugins::SESSION;
  $core = new Foswiki::Plugins::MetaDataPlugin::Core($session);

  return 0;
}


##############################################################################
sub initPlugin {

  # register macro handlers
  Foswiki::Func::registerTagHandler('RENDERMETADATA', sub {
    my $session = shift;
    return $core->RENDERMETADATA(@_);
  });
  Foswiki::Func::registerTagHandler('NEWMETADATA', sub {
    my $session = shift;
    return $core->NEWMETADATA(@_);
  });

  # register meta definitions
  registerMetaData();

#  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaDataPlugin", "get", sub {
#     my $session = shift;
#    return $core->jsonRpcGet(@_);
#  });

#  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaDataPlugin", "save", sub {
#     my $session = shift;
#    return $core->jsonRpcSave(@_);
#  });

#  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaDataPlugin", "update", sub {
#     my $session = shift;
#    return $core->jsonRpcUpdate(@_);
#  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaDataPlugin", "delete", sub {
    my $session = shift;
    return $core->jsonRpcDelete(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaDataPlugin", "lock", sub {
    my $session = shift;
    return $core->jsonRpcLockTopic(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaDataPlugin", "unlock", sub {
    my $session = shift;
    return $core->jsonRpcUnlockTopic(@_);
  });

  return 1;
}

##############################################################################
sub finishPlugin {
  $core = undef;
}

##############################################################################
sub registerDeleteHandler {
  return $core->registerDeleteHandler(@_);
}

##############################################################################
sub registerSaveHandler {
  return $core->registerSaveHandler(@_);
}

##############################################################################
sub beforeSaveHandler { 
  $core->beforeSaveHandler(@_); 
}

##############################################################################
sub registerMetaData {
  my $topics = shift;

  my $session = $Foswiki::Plugins::SESSION;
  my $baseWeb = $session->{webName};

  $topics = Foswiki::Func::getPreferencesValue("WEBMETADATA") || ''
    unless defined $topics;

  foreach my $item (split(/\s*,\s*/, $topics)) {
    my ($web, $topic) = Foswiki::Func::normalizeWebTopicName($baseWeb, $item);
    my $metaDef = getMetaDataDefinition($web, $topic);
    next unless defined $metaDef;
    my ($key) = topicName2MetaData($topic);
    #print STDERR "meta data key = $key\n";
    Foswiki::Meta::registerMETA($key, %$metaDef); 
  }
}

##############################################################################
# convert a web.topic pointing to a DataForm definition to a pair
# (key, alias) used to register metadata types based on this DataForm
sub topicName2MetaData {
  my $topic = shift;

  my $session = $Foswiki::Plugins::SESSION;
  my $baseWeb = $session->{webName};

  # 1. strip off the the web part
  (undef, $topic) = Foswiki::Func::normalizeWebTopicName($baseWeb, $topic);

  # 2. generate alias which are all lowercase and strip off any ...Topic suffix
  # from the DataForm name
  my $alias = $topic;
  $alias =~ s/Topic$//; 
  $alias =~ s/Form$//; 
  $alias = lc($alias);

  # 3. the real metadata key used to register it is the upper case version
  # of the alias
  my $key = uc($alias);

  return ($key, $alias);
}

##############################################################################
sub getMetaDataDefinition {
  my ($web, $topic) = @_;

  return unless Foswiki::Func::topicExists($web, $topic);

  my $formDef;
  my $session = $Foswiki::Plugins::SESSION;

  try {
    $formDef = new Foswiki::Form($session, $web, $topic);
  } catch Error::Simple with {

    # just in case, cus when this fails it takes down more of foswiki
    Foswiki::Func::writeWarning("MetaDataPlugin::getMetaDataDefinition() failed for $web.$topic: ".shift);

  } catch Foswiki::AccessControlException with {
    # catch but simply bail out
    #print STDERR "can't access form at $web.$topic in getMetaDataDefinition()\n";

    # SMELL: manually invalidate the forms cache for a partially build form object 
    if (exists $session->{forms}{"$web.$topic"}) {
      #print STDERR "WARNING: bug present in Foswiki::Form - invalid form object found in cache - deleting it manually\n";
      delete $session->{forms}{"$web.$topic"};
    }

  };

  return unless defined $formDef; # Hm, or do we create an empty record?

  my @other = ();
  my @require = ();

  push @require, 'name'; # is always required

  if (defined $formDef) {
    foreach my $field (@{$formDef->getFields}) {
      my $name = $field->{name};
      if ($field->isMandatory) {
        push @require, $name;
      } else {
        push @other, $name;
      }
    }
  }

  my ($key, $alias) = topicName2MetaData($topic);
  my $metaDef = {
    alias => $alias,
    many => 1,
    form => $web.'.'.$topic,
  };

  $metaDef->{require} = [ @require ] if @require;
  $metaDef->{other} = [ @other ] if @other;

  return $metaDef;
}

1;
