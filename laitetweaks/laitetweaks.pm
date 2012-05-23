# Gmusicbrowser: Copyright (C) 2005-2011 Quentin Sculo <squentin@free.fr>
# laitetweaks: Copyright (C) Markus Klinga (laite) <laite@gmx.com>
#
# This file is a plugin to Gmusicbrowser.
# It is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation.

=gmbplugin LAITETWEAKS
name	Laitetweaks
title	Laitetweaks
=cut

# This plugin is merely a 'holding place' for my personal tweaks
# Use if freely, don't oppress.
#   -laite

# TODO
#

package GMB::Plugin::LAITETWEAKS;
use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_LAITETWEAKS_',

};
use Gtk2::Gdk::Keysyms;
use base 'Gtk2::Box';
use base 'Gtk2::Dialog';
use utf8;

::SetDefaultOptions(OPT, TimeAgo => 1, QueueStraight => 0, QueueAlbum => 0, IntelligentLabelTotal => 1, FilterThis => 1);

sub TimeAgo
{
	my $ID = shift;
	my $sec = Songs::Get($ID,'lastplay');
	my $diff = time - $sec;
	
	return "n/a" if ($sec == 0);

	if ($diff>31536000) {return ::__("%d year ago","%d years ago",int($diff/31536000));}
	elsif ($diff > 2592000) {return ::__("%d month ago","%d months ago",int($diff/2592000));}
	elsif ($diff > 602280) {return ::__("%d week ago","%d weeks ago",int($diff/604800));}
	elsif ($diff > 86400) {return ::__("%d day ago","%d days ago",int($diff/86400));}
	elsif ($diff > 3600) {return ::__("%d hour ago","%d hours ago",int($diff/3600));}
	else {return "Just now";}
}
sub QueueStraight
{
	my @l=@_;
	Songs::SortList(\@l,$::Options{SavedSorts}{$::Options{OPT.'SortMode'}}) if @l>1;
	@l=grep $_!=$::SongID, @l  if @l>1 && defined $::SongID;
	$::Queue->Push(\@l);
}
sub QueueAlbum
{
	my $originalID = shift;
	my $IDs = AA::GetIDs('album',Songs::Get_gid($originalID,'album'));
	my $sortmode = ($::Options{OPT.'QueueStraight'})? $::Options{SavedSorts}{$::Options{OPT.'SortMode'}} : 'album_artist date album track title filename';
	return unless ($::SongID);
	Songs::SortList($IDs,$sortmode);

	my $currenttrack = Songs::Get($::SongID,'track');
	my @oktracks = ();
	
	for my $id (@$IDs)
	{
		next if ($id == $::SongID);
		next if (Songs::Get($id,'track') <= $currenttrack);
		push @oktracks,$id;
	}
	$::Queue->Push(\@oktracks) if (scalar@oktracks);
}

sub intellimode_Set
{	my $self=shift;
	::Watch($self,'Selection_'.$self->{group}, \&LabelTotal::QueueUpdateFast);
	::WatchFilter($self,$self->{group},	\&LabelTotal::QueueUpdateFast);
	::Watch($self, SongsAdded	=>	\&LabelTotal::SongsChanged_cb);
	::Watch($self, SongsRemoved	=>	\&LabelTotal::SongsChanged_cb);
}
sub intellimode_Update
{	
	my $self=shift;
	my $songlist=::GetSonglist($self);
	my $filter=::GetFilter($self);

	if ($songlist)
	{
		my @list=$songlist->GetSelectedIDs;
		if (scalar@list > 1){ return _('Selected : '), \@list,  ::__('%d song selected','%d songs selected',scalar@list); }
	}

	my $array=$filter->filter;
	return _("Filter : "), $array, $filter->explain;
}



######################################################
sub EnableOptions
{

	if ($::Options{OPT.'TimeAgo'}) {
		$GMB::Expression::vars2{song}{timeago} = ['GMB::Plugin::LAITETWEAKS::TimeAgo($arg->{ID})', undef,'CurSong'];
	}

	if ($::Options{OPT.'QueueAlbum'}) {
		for (@Layout::MenuQueue)
		{ 
			if (($_->{label}) and ($_->{label} =~ /^Queue album$/)) { $Layout::MenuQueue[0]->{code} =  sub { GMB::Plugin::LAITETWEAKS::QueueAlbum($_[0]{ID}); }; last;}
		}
	}

	if ($::Options{OPT.'QueueStraight'}) {
		for (@::SongCMenu) 
		{
			if (($_->{label}) and ($_->{label} =~ /^Enqueue Selected$/)) { $_->{code} = sub { GMB::Plugin::LAITETWEAKS::QueueStraight(@{ $_[0]{IDs} }); }; last; }
		}
	}
	
	if ($::Options{OPT.'IntelligentLabelTotal'})
	{
		$LabelTotal::Modes{intelligent}{label} = "Filter/selected";
		$LabelTotal::Modes{intelligent}{setup} = \&GMB::Plugin::LAITETWEAKS::intellimode_Set;
		$LabelTotal::Modes{intelligent}{update} = \&GMB::Plugin::LAITETWEAKS::intellimode_Update;
		$LabelTotal::Modes{intelligent}{delay} = 500;
	}
	
	if ($::Options{OPT.'FilterThis'})
	{
		for (@FilterPane::cMenu) 
		{
			if (($_->{label}) and ($_->{label} =~ /^Play$/)) { 
				$_->{code} = sub { ::Select(filter=>$_[0]{filter});}; 
				$_->{label} = "Filter this";
				$_->{stockicon} = 'gmb-filter';
				$_->{id} = 'filter';
				last; 
			}
		}
	}
}

sub Start
{	
	unless (defined $::Options{OPT.'SortMode'})
	{
		my @modes = sort keys %{$::Options{SavedSorts}};
		$::Options{OPT.'SortMode'} = $modes[0];
	}
	EnableOptions();
}
sub Stop
{
		
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	
	my $button=Gtk2::Button->new(_"Refresh options");
	$button->signal_connect(clicked => sub {EnableOptions();});

	my $check1=::NewPrefCheckButton(OPT."TimeAgo",'Add TimeAgo as column item', horizontal=>1,cb => \&EnableOptions);
	my $check2=::NewPrefCheckButton(OPT."QueueAlbum",'Only queue remaining songs with \'Queue Album\'', horizontal=>1,cb => \&EnableOptions);

	my @p = ();
	for my $mode (sort keys %{$::Options{SavedSorts}}) { push @p, $mode;}
	my $pmcombo= ::NewPrefCombo( OPT.'SortMode', \@p);
	my $check3=::NewPrefCheckButton(OPT."QueueStraight",'Always queue with:', horizontal=>1,cb => \&EnableOptions,widget=>$pmcombo);

	my $check4=::NewPrefCheckButton(OPT."IntelligentLabelTotal",'Add Filter/selected mode to LabelTotal', horizontal=>1,cb => \&EnableOptions);
	my $check5=::NewPrefCheckButton(OPT."FilterThis",'Show option to filter group from filterpane instead of playing it ', horizontal=>1,cb => \&EnableOptions);

	
	$vbox = ::Vpack($check1,$check2,,$check3,$check4,$check5,$button);	
	
	return $vbox;
}


1