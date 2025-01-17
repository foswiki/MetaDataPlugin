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

package Foswiki::Plugins::MetaDataPlugin;

=begin TML

---+ package Foswiki::Plugins::MetaDataPlugin

base class to hook into the foswiki core

=cut

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Contrib::JsonRpcContrib ();
use Foswiki::Plugins::MetaDataPlugin::Core();
use Foswiki::Plugins::RenderPlugin();
use Error qw( :try );

use Foswiki::Request ();

BEGIN {
  # Backwards compatibility for Foswiki 1.1.x
  unless (Foswiki::Request->can('multi_param')) {
    no warnings 'redefine'; ## no critic
    *Foswiki::Request::multi_param = \&Foswiki::Request::param;
    use warnings 'redefine';
  }
}

our $VERSION = '7.71';
our $RELEASE = '%$RELEASE%';
our $SHORTDESCRIPTION = 'Bring custom meta data to wiki apps';
our $LICENSECODE = '%$LICENSECODE%';
our $NO_PREFS_IN_TOPIC = 1;
our $core;
our $importer;
our $exporter;
our %doneRegisterMeta;

=begin TML

---++ initPlugin($topic, $web, $user) -> $boolean

initialize the plugin, automatically called during the core initialization process

=cut

sub initPlugin {

  # register macro handlers
  Foswiki::Func::registerTagHandler('RENDERMETADATA', sub {
    my $session = shift;
    return getCore()->RENDERMETADATA(@_);
  });
  Foswiki::Func::registerTagHandler('NEWMETADATA', sub {
    my $session = shift;
    return getCore()->NEWMETADATA(@_);
  });
  Foswiki::Func::registerTagHandler('EXPORTMETADATA', sub {
    my $session = shift;
    return getCore()->EXPORTMETADATA(@_);
  });
  Foswiki::Func::registerTagHandler('IMPORTMETADATA', sub {
    my $session = shift;
    return getCore()->IMPORTMETADATA(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaDataPlugin", "get", sub {
    my $session = shift;
    return getCore()->jsonRpcGet(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaDataPlugin", "save", sub {
    my $session = shift;
    return getCore()->jsonRpcSave(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaDataPlugin", "delete", sub {
    my $session = shift;
    return getCore()->jsonRpcDelete(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaDataPlugin", "lock", sub {
    my $session = shift;
    return getCore()->jsonRpcLockTopic(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaDataPlugin", "unlock", sub {
    my $session = shift;
    return getCore()->jsonRpcUnlockTopic(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaDataPlugin", "import", sub {
    return getImporter(shift)->jsonRpcImport(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaDataPlugin", "export", sub {
    return getExporter(shift)->jsonRpcExport(@_);
  });

  if (exists $Foswiki::cfg{Plugins}{SolrPlugin} && $Foswiki::cfg{Plugins}{SolrPlugin}{Enabled}) {
    require Foswiki::Plugins::SolrPlugin;
    Foswiki::Plugins::SolrPlugin::registerIndexTopicHandler(sub {
      return getCore()->solrIndexTopicHandler(@_);
    });
  }

  if ($Foswiki::Plugins::VERSION < 2.6 && exists $Foswiki::cfg{Plugins}{DBCachePlugin} && $Foswiki::cfg{Plugins}{DBCachePlugin}{Enabled}) {
    registerMetaData(); 
  }

  # rest handler required for javascript metadata view interface
  Foswiki::Plugins::RenderPlugin::registerAllowedTag("RENDERMETADATA");

  # SMELL: can't register meta data by now as the core and plugins aren't fully initialized yet
  # registerMetaData(); 

  return 1;
}
=begin TML

---++ lateInitPlugin() 

Foswiki::Plugins::VERSION >= 2.6

register all known meta data now that all plugins have been init'ed

=cut

sub lateInitPlugin {
  registerMetaData(); 
}

=begin TML

---++ getCore() -> $core

returns a singleton Foswiki::Plugins::MetaDataPlugin::Core object for this plugin; a new core is allocated 
during each session request; once a core has been created it is destroyed during =finishPlugin()=

=cut

sub getCore {
  my $session = shift;

  unless (defined $core) {
    $core = Foswiki::Plugins::MetaDataPlugin::Core->new($session);
  }
 
 return $core; 
}

=begin TML

---++ getImporter() -> $importer

returns a singleton Foswiki::Plugins::MetaDataPlugin::Importer object for this plugin

=cut

sub getImporter {
  my $session = shift;

  unless (defined $importer) {
    require Foswiki::Plugins::MetaDataPlugin::Importer;
    $importer = Foswiki::Plugins::MetaDataPlugin::Importer->new($session, getCore());
  }
  return $importer;
}

=begin TML

---++ getExporter() -> $exporter

returns a singleton Foswiki::Plugins::MetaDataPlugin::Exporter object for this plugin

=cut

sub getExporter {
  my $session = shift;

  unless (defined $exporter) {
    require Foswiki::Plugins::MetaDataPlugin::Exporter;
    $exporter = Foswiki::Plugins::MetaDataPlugin::Exporter->new($session, getCore());
  }
  return $exporter;
}

=begin TML

---++ finishPlugin

finish the plugin and the core if it has been used,
automatically called during the core initialization process

=cut

sub finishPlugin {
  if (defined $core) {
    $core->finish();
    undef $core;
  }

  if (defined $importer) {
    $importer->finish();
    undef $importer;
  }

  if (defined $exporter) {
    $exporter->finish();
    undef $exporter;
  }

  %doneRegisterMeta = (); # do above call in a lazy way
}



=begin TML

---++ registerDeleteHandler() 

register a handler to be called when a metedata record is deleted

=cut

sub registerDeleteHandler {
  return getCore()->registerDeleteHandler(@_);
}

=begin TML

---++ registerSaveHandler() 

register a handler to be called when a metedata record is deleted

=cut

sub registerSaveHandler {
  return getCore()->registerSaveHandler(@_);
}

=begin TML

---++ beforeSaveHandler () 

called during the core's save procedure on anything

=cut

sub beforeSaveHandler { 
  getCore()->beforeSaveHandler(@_); 
}

=begin TML

---++ registerMetaData() 

register a new meta data record type

=cut

sub registerMetaData {
  my $baseWeb = shift;

  my $session = $Foswiki::Plugins::SESSION;
  $baseWeb //= $session->{webName};
  $baseWeb =~ s/\//\./g;
  my $baseTopic = $session->{topicName};

  return if $doneRegisterMeta{$baseWeb};
  $doneRegisterMeta{$baseWeb} = 1;

  Foswiki::Func::pushTopicContext($baseWeb, $baseTopic);
  my $topics = Foswiki::Func::getPreferencesValue("WEBMETADATA") || '';
  Foswiki::Func::popTopicContext();

  $topics =~ s/%WEB%/$baseWeb/g;
  $topics =~ s/%TOPIC%/$baseTopic/g;

  foreach my $item (split(/\s*,\s*/, $topics)) {
    my ($web, $topic) = Foswiki::Func::normalizeWebTopicName($baseWeb, $item);
    my $metaDef = getMetaDataDefinition($web, $topic);
    #print STDERR "reading $web.$topic....metaDef=".(defined $metaDef? $metaDef->{key}:'undef')."\n";
    next unless defined $metaDef;
    Foswiki::Meta::registerMETA($metaDef->{key}, %$metaDef); 
  }
}

=begin TML

---++ ObjectMethod topicName2MetaData($topic) 

convert a web.topic pointing to a DataForm definition to a pair
(key, alias) used to register metadata types based on this DataForm

=cut

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

=begin TML

---++ ObjectMethod getMetaDataDefinition($web, $topic) -> $def

=cut

sub getMetaDataDefinition {
  my ($web, $topic) = @_;

  return unless Foswiki::Func::topicExists($web, $topic);

  my $formDef;
  my $session = $Foswiki::Plugins::SESSION;

  try {
    $formDef = Foswiki::Form->new($session, $web, $topic);
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
    key => $key,
    alias => $alias,
    many => 1,
    form => $web.'.'.$topic,
  };

  $metaDef->{require} = [ @require ] if @require;
  $metaDef->{other} = [ @other ] if @other;

  return $metaDef;
}

1;
