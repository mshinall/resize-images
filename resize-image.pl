#!/usr/bin/perl -w
#
# https://github.com/mshinall
#
# Use ImageMagick identify and convert to bulk resize one or more images
# to a different size
# *** Need to have ImageMagick installed

use strict;
use utf8;
use Log::Log4perl;
use File::Basename;
use YAML;
use File::Copy qw(copy);
use File::Path qw(make_path);

sub getImage($$);
sub saveImage($$);
sub processImage($);
sub getImageProperties($);
sub resizeImage($$;$);
sub systemCall($);
sub getTimestamp();

#my $basedir = File::Basename::dirname($0);
my $SCRIPT = File::Basename::basename($0);

if((scalar(@ARGV) < 4) ||
    ($ARGV[0] !~ /^\d+x\d+$/) ||
    ($ARGV[1] =~ /\W/g) ||
    ($ARGV[2] !~ /^\d+$/)) {
    print("Usage: ${SCRIPT} GEOMETRY BGCOLOR MAX_KB IMAGE_FILE [IMAGE_FILE...]\n");
    exit(1);
}

my ($geometry, $bgcolor, $maxkb, @files) = @ARGV;


my $PROPS = {
    'qualityStep' => 1, #percent
    'throttle' => 0, #seconds
    'geometry' => "${geometry}",
    'bgcolor' => "${bgcolor}",
    'maxkb' => int($maxkb),
    'processDir' => "resized-${geometry}-${bgcolor}-${maxkb}kb-${\&getTimestamp()}",    
};

my $logProps = {
     'log4perl.logger' => 'INFO, screen'
    ,'log4perl.appender.screen' => 'Log::Log4perl::Appender::Screen'
    ,'log4perl.appender.screen.layout' => 'Log::Log4perl::Layout::PatternLayout'
    ,'log4perl.appender.screen.layout.ConversionPattern' => '%d %p %l - %m%n'
};

Log::Log4perl->init($logProps);
my $logger = Log::Log4perl->get_logger();

if(! -d $PROPS->{'processDir'}) {
    make_path($PROPS->{'processDir'});
}

foreach(@files) {
    processImage($_);
    $logger->info('');
}
$logger->info('Done.');
exit(0);

sub saveImage($$) {
    $logger->trace("ENTERING");
    my ($file, $content) = @_;
    $logger->info("Saving image to '${file}' ...");    
    my $imagefh;
    open($imagefh, ">${file}");
    print($imagefh $content);
    close($imagefh);
    $logger->trace("EXITING");    
    return (-f $file);
}

sub processImage($) {
    $logger->trace("ENTERING");
    my ($oFile) = @_;
    my $filename = File::Basename::basename($oFile);
    my $pFile = $PROPS->{'processDir'} . '/' . $filename;
    copy($oFile, $pFile);
    $logger->info("Processing image '${oFile}' ...");
    my $oProps = getImageProperties($oFile);
    
    my $geo = $PROPS->{'geometry'};
    if($oProps->{'Geometry'} !~ /^$geo/) {
        resizeImage($oFile, $pFile);
    }
    
    my $pProps = getImageProperties($pFile);
    while(int($pProps->{'Filesize'}) >= $PROPS->{'maxkb'}) {
        my $oldQuality = $pProps->{'Quality'};
        my $newQuality = $oldQuality - $PROPS->{'qualityStep'};
        resizeImage($oFile, $pFile, $newQuality);
        sleep($PROPS->{'throttle'});
        $pProps = getImageProperties($pFile);        
    }
    $logger->trace("EXITING");        
}

sub getImageProperties($) {
    $logger->trace("ENTERING");
    my ($file) = @_;
    $logger->trace("Getting image properties for '${file}' ...");    
    my $props = {};
    my $cmd = "identify -verbose '${file}'";
    my $output = systemCall($cmd);    
    foreach(split("\n", $output)) {
        $_ =~ /^\s*Geometry:\s*(.*)/ && do {
            $props->{'Geometry'} = $1;
        };
        #$_ =~ /^\s*Filesize:\s*([\d.]*)/ && do {
        #    $props->{'Filesize'} = ($1 * 1);
        #};
        $_ =~ /^\s*Quality:\s*([\d.]*)/ && do {
            $props->{'Quality'} = ($1 * 1);
        };                       
    }
    $props->{'Filesize'} = ((-s $file) / 1000);
    $logger->debug("image properties for '${file}': " . join(", ", %$props));
    $logger->trace("EXITING");    
    return $props;
}

sub resizeImage($$;$) {
    $logger->trace("ENTERING");
    my ($oFile, $pFile, $quality) = @_;
    my $logMsg = "Converting image: resizing '${oFile}' geometry to ${\$PROPS->{'geometry'}}";
    if($quality) {
        $logMsg .= " and quality to ${quality}";
    }
    $logMsg .= " ...";
    $logger->info($logMsg);    
    my $cmd = "convert '${oFile}' -resize ${\$PROPS->{'geometry'}} -bordercolor ${\$PROPS->{'bgcolor'}} -border ${\$PROPS->{'geometry'}} -gravity center -crop ${\$PROPS->{'geometry'}}+0+0";
    if($quality) {
        $cmd .= " -quality ${quality}%";
    }
    $cmd .= " '${pFile}'";
    my $output = systemCall($cmd);
    $logger->trace("EXITING");    
    return $output;
}

sub systemCall($) {
    $logger->trace("ENTERING");
    my ($cmd) = @_;
    $logger->trace($cmd);    
    my $pipefh;
    open($pipefh, "${cmd} 2>&1 |") or logger->logdie("Cannot open handle for system command '${cmd}': $!");
    my $output = "";
    while(<$pipefh>) {
        $output .= $_;
    }
    close($pipefh);
    $logger->trace($output);
    $logger->trace("EXITING");    
    return $output;
}

sub timeInMins($) {
    $logger->trace("ENTERING");
    my ($string) = @_;
    my $mins = 0;
    if($string =~ /^(\d+)\s*Min/i) {
        $mins = int($1);
    } elsif($string =~ /^(\d+)\s*Hr\s*(\d+)\s*Min/i) {
        $mins = (int($1) * 60) + int($2);
    } else {}
    $logger->trace("EXITING");    
    return $mins
}

sub getTimestamp() {
    my @localtime = localtime();
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = @localtime;
    return sprintf("%4d%02d%02d%02d%02d%02d", ($year + 1900), ($mon + 1), $mday, $hour, $min, $sec);
}

1;
