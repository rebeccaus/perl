#!/usr/bin/perl -w

use strict;
use HTTP::Request;
use Data::Dumper;
use XML::Simple;
use LWP;

#curl executable location
my $curl="/usr/bin/curl";

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;

my $feed_config = shift or die &usage; ##>> what is this part doing ?
my $Link_A = shift or die &usage;
#Split the command parameter into Link_A and SKEY ##>> if link_A is a file what it should include and in which content format?
my ($Link_A,$skey,$priority)= split(',',$Link_A);

if ( ! -f $feed_config )
   {
      print "\n'$feed_config' is not a file \n";
      &usage; ##>> what is this part doing?
   }

if (( ! -f $curl ) || ( ! -x $curl ))
   {
      print "'$curl' - not found or non-executable\n";
      exit 1;
   }

my $scope="";
my $nt_id="";

#Jenkins variables ##>>>where do i include this variables ?
my $lastBuild;
my $lastSuccessfulBuild;
my $lastStableBuild;
my $lastBuildStatus;
my $previousBuild;
my $previousBuildStatus;
my $action;
#$ENV{JOB_URL}="https://localhost:8080/jenkins/job/agent/";
#$ENV{JOB_NAME}="agent";
#$ENV{BUILD_NUMBER}="1";
#$ENV{BUILD_URL}="https://localhost:8080/jenkins/job/agent/1/console";


#read feed_config
my $feed_config_ref=&readopeninc($feed_config); #>>what is this part doing ? are values defined in feed_config for feed_config_ref ?
my %feed_values=%$feed_config_ref;

my $juser=$feed_values{'j.user'}; #> is this value defined in feed_config?
my $japi=$feed_values{'j.api'};
my $curlopts="-k -u $juser:$japi" if ($japi && $juser);

my $job_url="$ENV{JOB_URL}";
my $job_name="$ENV{JOB_NAME}";
my $build_number="$ENV{BUILD_NUMBER}";
my $build_url="$ENV{BUILD_URL}";
my $job1;

#nt ids
my %nt;
$nt{"user"}="00324";


#Extract scope from job_name and assign priority
($scope,$job1)=($job_name =~ /(.*?)_(.*)/);

my $subject="[$scope]: $job_name:$build_number";
my $createxml=""; #> is this creating a xml variable and feeding values in or the value is defined explicitly and it is taking from there ?
my $updatexml="";
my $closexml="";
my $statusxml="";
my $evlink="";

#Script variables #> where is this variables are defined do i need to explicitly define this?
my $date=`date +%Y%m%d`;
#my $logdir="/tmp/";
my $logdir="./";
my $LOGFILE="$logdir"."Jenkins_feed.log";
my $inclog="$logdir"."feed_INC.txt";
my $issueid;
my $desc = <<EODESC;
*************  $job_name Details ************* I#>> is this part doing something?

feed            : Jenkins Jobs
Check Name      : $job_name
URL             : $build_url
DESC            : $Link_A
EODESC

$lastBuild=`$curl $curlopts $job_url/lastBuild/buildNumber 2>/dev/null`;
$lastSuccessfulBuild=`$curl $curlopts $job_url/lastSuccessfulBuild/buildNumber 2>/dev/null`;
$lastStableBuild=`$curl $curlopts $job_url/lastStableBuild/buildNumber 2>/dev/null`;
$lastBuildStatus=(`$curl $curlopts $job_url/lastBuild/api/json?tree=result 2>/dev/null | jq -r .result`);
$lastBuildStatus =~ s/^\s+|\s+$//g ;

$previousBuild=$lastBuild-1;
$previousBuildStatus=(`$curl $curlopts $job_url/${previousBuild}/api/json?tree=result 2>/dev/null | jq -r .result`);
$previousBuildStatus =~ s/^\s+|\s+$//g ;

#Search and remove '}' '"' from json's result string

$lastBuildStatus=~s/\}|\"//g;
$previousBuildStatus=~s/\}|\"//g;

print "***** INFO - lastBuild:$lastBuild,lastSuccessfulBuild: $lastSuccessfulBuild,lastStableBuild: $lastStableBuild,lastBuildStatus: $lastBuildStatus,previousBuild: $previousBuild,previousBuildStatus: $previousBuildStatus\n";

#read existing issue >> is inclog file created automatically or it has to be created explicitly if yes in which path?
my $openinc_ref;
my %openinc;
if ( -f $inclog )
   {
      $openinc_ref = &readopeninc($inclog);
      %openinc=%$openinc_ref;
   }
#Assign variables from config file

my $usergroup=$feed_values{''};
my $checkid=$feed_values{'checkid'};
my $team=$feed_values{'team'};
my $feedurl=$feed_values{'feedurl'};
my $usr=$feed_values{'usr'};
my $pwd=$feed_values{'pwd'};
my $category=$feed_values{'category'};
my $process=$feed_values{'process'};
#Get the skey passed from jenkins job or take default
$skey=$skey||"JENKINS00001016"; # >> here is it passing from jenkins job/taking default, how do I make it to take default one?
$priority=$priority||$feed_values{'priority'};
$nt_id=$nt{$scope}||$feed_values{'nt_id'};
#Build status = FAILURE or SUCCESS 
#||Previous Build||Current Build||feed Webservice||Comment||
#|Pass|Pass|No Action| |
#|Fail|Fail|A1Sfeed/feed_issue_UPDATE|Add a new comment with failed build number
#|Fail|Pass|A1Sfeed/feed_issue_CLOSE   |*Close* with pass buildnumber as comment
#|Pass|Fail|A1Sfeed/feed_issue_CREATION|*Create* with buildnumber as comment

if (( $previousBuildStatus eq "SUCCESS" ) && ( $lastBuildStatus eq "SUCCESS" ))
   {
      $action="none";
   }
elsif (( $previousBuildStatus eq "FAILURE" ) && ( $lastBuildStatus eq "FAILURE" ))
   {
      $action="update";
      &update;
   }
elsif (( $previousBuildStatus eq "FAILURE" ) && ( $lastBuildStatus eq "SUCCESS" ))
   {
      $action="close";
      &closefeed;
   }
elsif (( $previousBuildStatus eq "SUCCESS" ) && ( $lastBuildStatus eq "FAILURE" ))
   {
      $action="create";
      &create;
   }
else
   {
      $action="invalid";
      print "'$previousBuildStatus' or '$lastBuildStatus' is unknown\n";
      exit;
   }


my $output = <<"OUTPUT";
Action:'$action' #>> do in need to define the $action? what exactly it is doing?
----------------------------------------- ##>> what is this part doing?
Field   |Previous Build | Current Build |
-----------------------------------------
Build # | $previousBuild\t\t| $lastBuild\t\t|
Status  | $previousBuildStatus\t| $lastBuildStatus\t|
-----------------------------------------
OUTPUT

print "$output\n";

#Function to Create issue ##>> will this info be stored anywhere in system if yes which path?
sub create
   {
      &createinput;
      #print "$createxml\n";
      open(FD, ">> $LOGFILE") or warn "Cannot create '$LOGFILE':$!\n";
      if (&sendCreate("new", $createxml, $feedurl, $usr, $pwd) eq 1)
         {
            print FD localtime()."- DEBUG : Created a new issue in feed $job_name : $issueid\n";
            open(INCFH, ">> $inclog") or warn "Cannot create '$inclog':$!\n";
            print INCFH "$job_name=$issueid\n";
            close(INCFH);
            print FD localtime()."- DEBUG : $LOGFILE updated with new issue $issueid details\n";
         }
      else
         {
            print FD localtime()."- DEBUG: Create issue in feed FAILED !!  \n";
         }
    close(FD);
   }

#Function to create createxml
sub createinput
   {
      $createxml = <<EOXML;
        <?xml version="1.0" encoding="UTF-8"?>
           <soap:Envelope
                  xmlns:soap="http://www.w3.org/2003/05/soap-envelope"
                  xmlns:urn="urn:jjk-com:document:jjk:rfc:functions">
      <soap:Header/>
         <soap:Body>
            <urn:_-A1Sfeed_-feed_issue_CREATION>
            <IV_CHECK_GROUP>$usergroup</IV_CHECK_GROUP>
            <IV_CHECK_ID>$checkid</IV_CHECK_ID>
            <IV_EVENT_KEY>$skey</IV_EVENT_KEY>
            <IV_DESCRIPTION>$desc</IV_DESCRIPTION>
            <IV_issue_PROCESS>SYSTEM issue</IV_issue_PROCESS>
            <IV_ISSUE_CATEGORY>$category</IV_ISSUE_CATEGORY>
            <IV_TEAM>$team</IV_TEAM>
            <IV_PRIORITY>$priority</IV_PRIORITY>
            <IV_TENANT_ID>$nt_id</IV_TENANT_ID>
            <IV_PROCESS>$process</IV_PROCESS>
            <IV_SUBJECT>$subject</IV_SUBJECT>
         </urn:_-A1Sfeed_-feed_issue_CREATION>
      </soap:Body>
   </soap:Envelope>
EOXML
   }

#Function to send the createdxml to webservice
sub sendCreate
   {
      my $createmode = $_[0]; #>> what this part is doing what is [0] ,[1] etc ..?
      my $passedXml = $_[1];
      my $url = $_[2];
      my $usr = $_[3];
      my $pwd = $_[4];
      my $returnvalue;
      my $xmlParser = new XML::Simple();

      print FD localtime()."- DEBUG : Calling do_webservice function";
      my $response = &do_webservice( $url, $usr, $pwd, $passedXml );
      print FD localtime()."- DEBUG: Executed do_webservice function \n";
      print FD localtime()."- DEBUG: Response from the webservice call is $response \n";

      my $r_content = $response->content;
      my $r_code = $response->code;
      my $r_message = $response->message;

      print FD localtime()."- DEBUG: Response content is $r_content, Response Code is $r_code, Response Message is $r_message \n";
      my $r_all = <<EORESPONSE;
         HTTP Code: $r_code
         HTTP Message: $r_message
         HTTP Content: $r_content
EORESPONSE

      my $mess = $xmlParser->XMLin($r_content);
      #print Dumper($mess);
      $issueid = $mess->{"env:Body"}{"n0:_-A1Sfeed_-feed_issue_CREATIONResponse"}{"EV_issue_ID"};
      $evlink = $mess->{"env:Body"}{"n0:_-A1Sfeed_-feed_issue_CREATIONResponse"}{"EV_LINK"};
      print FD localtime()."- DEBUG : issue ID is $issueid\n";
      print FD localtime()."- DEBUG : EV_LINK is $evlink\n";
      if ( ref($evlink) eq "HASH" )
         {
            print "\n\n*****WARNING : feed Alert not created : Please contact admin@domain.com*****\n\n";
            print "ERROR:\n".Dumper($mess);
            print "INPUT:\n$passedXml\n";
         }
      else
         {
             print "\nNew issue created : $evlink\n\n";
         }

      if ($r_code eq '200')
         {
            my $mess = $xmlParser->XMLin($r_content);
            #print Dumper($mess);
            print FD localtime()."- DEBUG : Message is $mess\n";
            print FD localtime()."- DEBUG : xmlParser is $xmlParser\n";
            print FD localtime()."- DEBUG : Content is $r_content\n";
            $issueid = $mess->{"env:Body"}{"n0:_-A1Sfeed_-feed_issue_CREATIONResponse"}{"EV_issue_ID"};
            print FD localtime()."- DEBUG : issue ID is $issueid\n";
            return 1;
         }
   }

#Function to read open issues and feed config file #>> what this part is doing?
#file content
#property=value #>> is there any explicit format of porperty and value?
sub readopeninc
   {
      my $property;
      my $value;
      my %openinc;
      my $input=shift;
      open(INCFH, "< $input") or warn "Cannot open for reading '$input':$!\n";
      while (<INCFH>)
         {
            chomp;                  # no newline
            s/^#.*//;                # no comments
            s/^\s+//;               # no leading white
            s/\s+$//;               # no trailing white
            next unless length;     # anything left?
            ($property, $value) = split(/\s*=\s*/, $_, 2);
            $openinc{$property} = $value;
         }
      close(INCFH);
      return \%openinc;
   }

#Function to update existing issue with failed build number
sub update
   {
      open(FD, ">> $LOGFILE") or warn "Cannot create '$LOGFILE':$!\n"; ##>> from where does this value is getting returned? is this from a path where the value is retuned
      if ( defined $openinc{$job_name} )
         {
#get status of existing issue id, if the status, then update, else create a new alert
            print "Existing issue id for job:$job_name - $openinc{$job_name}\n"; ##>> is this openinc a file stored in system or it is value read from another file ??
            if (&getstatus($openinc{$job_name}) =~ /(new|in process)/i)
               {
                  &createupdate;
                  print FD localtime()."- DEBUG :Updating comment for $openinc{$job_name}\n";
                  #print "$updatexml\n";
                  if (&sendUpdate("update", $updatexml, $feedurl, $usr, $pwd) eq 1)
                     {
                         print FD localtime()."- DEBUG : Update a new issue in feed $job_name : $issueid\n";
                     }
                  else
                     {
                        print FD localtime()."- DEBUG: Update issue in feed FAILED !!  \n";
                     }
               }
            else
               {
                  $action="re-create";
                  &removeinc($job_name);
                  &create;
                  print FD localtime()."- DEBUG : Created a new alert\n";
               }
            close(FD);
         }
      else
         {
#create a new alert, since the alert reference is not found in reference file
            $action="re-create";
            print FD localtime()."- DEBUG : Alert not found in reference file, created a new alert\n";
            close(FD);
            &create;
            print "INFO: $job_name - not found in '$inclog' for updating in feed\n";
         }
   }

#Function to create update xml
sub createupdate
   {
      $updatexml = <<EOXML;
        <?xml version="1.0" encoding="UTF-8"?>
           <soap:Envelope
                  xmlns:soap="http://www.w3.org/2003/05/soap-envelope"
                  xmlns:urn="urn:jjk-com:document:jjk:rfc:functions">
      <soap:Header/>
         <soap:Body>
            <urn:_-A1Sfeed_-feed_issue_UPDATE>
            <IV_issue_ID>$openinc{$job_name}</IV_issue_ID>
            <IV_NEW_COMMENT>$build_url - $lastBuildStatus</IV_NEW_COMMENT>
         </urn:_-A1Sfeed_-feed_issue_UPDATE>
      </soap:Body>
   </soap:Envelope>
EOXML
   }

#Function to send updatexml to webservice
sub sendUpdate
   {
      my $createmode = $_[0];
      my $passedXml = $_[1];
      my $url = $_[2];
      my $usr = $_[3];
      my $pwd = $_[4];
      my $returnvalue;
      my $xmlParser = new XML::Simple();
      print FD localtime()."- DEBUG : Calling do_webservice function";
      my $response = &do_webservice( $url, $usr, $pwd, $passedXml );
      print FD localtime()."- DEBUG: Executed do_webservice function \n";
      print FD localtime()."- DEBUG: Response from the webservice call is $response \n";

      my $r_content = $response->content;
      my $r_code = $response->code;
      my $r_message = $response->message;

      print FD localtime()."- DEBUG: Response content is $r_content, Response Code is $r_code, Response Message is $r_message \n";
      my $r_all = <<EORESPONSE;
         HTTP Code: $r_code
         HTTP Message: $r_message
         HTTP Content: $r_content
EORESPONSE

      my $mess = $xmlParser->XMLin($r_content);
      #print Dumper($mess);
      my $status = $mess->{"env:Body"}{"n0:_-A1Sfeed_-feed_issue_UPDATEResponse"}{"EV_OK"};
      print FD localtime()."- DEBUG : update status is $status", "\n";

      if ($r_code eq '200')
         {
            my $mess = $xmlParser->XMLin($r_content);
            #print Dumper($mess);
            print FD localtime()."- DEBUG : Message is $mess", "\n";
            print FD localtime()."- DEBUG : xmlParser is $xmlParser", "\n";
            print FD localtime()."- DEBUG : Content is $r_content", "\n";
            $issueid = $mess->{"env:Body"}{"n0:_-A1Sfeed_-feed_issue_UPDATEResponse"}{"EV_OK"};
            print FD localtime()."- DEBUG : update status is $status", "\n";
            return 1;
         }
   }

#Function to close existing issue with failed passed build number
sub closefeed
   {
      if ( defined $openinc{$job_name} )
         {
#if the alert status is new/in process, then close else no action in feed, remove from reference file and exit
            open(FD, ">> $LOGFILE") or warn "Cannot create '$LOGFILE':$!\n";
            if (&getstatus($openinc{$job_name}) =~ /(new|in process)/i)
               {
                  print "Closing existing issue $job_name - $openinc{$job_name}\n";
                  &createclose;
                  #print "$closexml\n";
                  if (&sendClose("close", $closexml, $feedurl, $usr, $pwd) eq 1)
                     {
                        print FD localtime()."- DEBUG : Close issue in feed $job_name : $issueid\n";
                     }
                  else
                     {
                        print FD localtime()."- DEBUG: Closing issue in feed FAILED !!  \n";
                     }
               }
            else
               {
                  print FD localtime()."- DEBUG: issue is not in now/in process stage, so NO action in feed\n";
                  print "issue is not in now/in process stage, so NO action in feed\n";
               }
#remove the issue/jobname from reference file
            &removeinc($job_name);
            close(FD);
         }
      else
         {
            print "INFO: $job_name - not found in '$inclog', so NO action in feed\n";
         }
   }

#Function to create close xml
sub createclose
   {
      $closexml = <<EOXML;
        <?xml version="1.0" encoding="UTF-8"?>
           <soap:Envelope
                  xmlns:soap="http://www.w3.org/2003/05/soap-envelope"
                  xmlns:urn="urn:jjk-com:document:jjk:rfc:functions">
      <soap:Header/>
         <soap:Body>
            <urn:_-A1Sfeed_-feed_issue_CLOSE>
            <IV_issue_ID>$openinc{$job_name}</IV_issue_ID>
            <IV_REASON>AUTO fixed : $build_url - $lastBuildStatus</IV_REASON>
         </urn:_-A1Sfeed_-feed_issue_CLOSE>
      </soap:Body>
   </soap:Envelope>
EOXML
   }

#Function to close
sub sendClose
   {
      my $createmode = $_[0];
      my $passedXml = $_[1];
      my $url = $_[2];
      my $usr = $_[3];
      my $pwd = $_[4];
      my $returnvalue;
      my $xmlParser = new XML::Simple();

      print FD localtime()."- DEBUG : Calling do_webservice function";
      my $response = &do_webservice( $url, $usr, $pwd, $passedXml );
      print FD localtime()."- DEBUG: Executed do_webservice function \n";
      print FD localtime()."- DEBUG: Response from the webservice call is $response \n";

      my $r_content = $response->content;
      my $r_code = $response->code;
      my $r_message = $response->message;

      print FD localtime()."- DEBUG: Response content is $r_content, Response Code is $r_code, Response Message is $r_message \n";
      my $r_all = <<EORESPONSE;
         HTTP Code: $r_code
         HTTP Message: $r_message
         HTTP Content: $r_content
EORESPONSE

      my $mess = $xmlParser->XMLin($r_content);
      #print Dumper($mess);
      my $status = $mess->{"env:Body"}{"n0:_-A1Sfeed_-feed_issue_CLOSEResponse"}{"EV_SUCCESS_FLAG"};
      print FD localtime()."- DEBUG : close status is $status", "\n";

      if ($r_code eq '200')
         {
            my $mess = $xmlParser->XMLin($r_content);
            #print Dumper($mess);
            print FD localtime()."- DEBUG : Message is $mess", "\n";
            print FD localtime()."- DEBUG : xmlParser is $xmlParser", "\n";
            print FD localtime()."- DEBUG : Content is $r_content", "\n";
            $issueid = $mess->{"env:Body"}{"n0:_-A1Sfeed_-feed_issue_CLOSEResponse"}{"EV_SUCCESS_FLAG"};
            print FD localtime()."- DEBUG : close status is $status", "\n";
            return 1;
         }
   }

#Function to get status of issueid
#Input - IV_issue_ID #>> from where the incdient_id is taken ?
#output - EV_STATUS_CODE, EV_STATUS_DESCRIPTION, ET_MESSAGES

sub getstatus
   {
      my $ininc=$_[0];
      $statusxml = <<EOXML;
        <?xml version="1.0" encoding="UTF-8"?>
           <soap:Envelope
                  xmlns:soap="http://www.w3.org/2003/05/soap-envelope"
                  xmlns:urn="urn:jjk-com:document:jjk:rfc:functions">
      <soap:Header/>
         <soap:Body>
            <urn:_-A1Sfeed_-GET_issue_STATUS>
            <IV_issue_ID>$ininc</IV_issue_ID>
         </urn:_-A1Sfeed_-GET_issue_STATUS>
      </soap:Body>
   </soap:Envelope>
EOXML

      my $xmlParser = new XML::Simple();
      my $response = &do_webservice( $feedurl, $usr, $pwd, $statusxml );
      my $r_content = $response->content;
      my $mess = $xmlParser->XMLin($r_content);
      my $incstatus = $mess->{"env:Body"}{"n0:_-A1Sfeed_-GET_issue_STATUSResponse"}{"EV_STATUS_DESCRIPTION"};
      print "issue status : $ininc = $incstatus\n";
      return "$incstatus";
   }

#Function to remove closed inc from log file ##>> where this log file should be created or generated in system?
sub removeinc
   {
      my $jobname=$_[0];
      delete $openinc{$jobname};
      open(INCFH, "> $inclog") or warn "Cannot create '$inclog':$!\n";
      foreach my $job(keys%openinc)
         {
            print INCFH "$job=$openinc{$job}\n";
         }
      close(INCFH);
   }

#Generic function to call feed webservice
sub do_webservice
   {
      my ( $weburl, $usr, $password, $webxml ) = @_;
      print FD "\nXML: \n$webxml\n";
      print FD "\nURL: \n$weburl\n";
      my $ua = LWP::UserAgent->new();
      #$ua->ssl_opts( verify_hostnames => 0 );
      $ua->proxy( 'https', "http://proxy.mellow.man.corp:8080" );
      my $r = HTTP::Request->new( "POST", $weburl );
      $r->header( "Content-Type" => "application/soap+xml;charset=UTF-8", "SOAPAction" => "", "user-agent" => "Hyperic" );
#      print "$usr -> '$password'\n";
      $r->authorization_basic( $usr, $password );
      $r->content($webxml);
      my $response = $ua->request($r);
      print FD localtime()."- DEBUG: Response is $response \n";
      return $response;
   }

#Usage function
sub usage ##>>>>>>>>>what does this function do will it take the config_file and Link_A from the path in system, is this config file = feed_config?
   {
my $usage=<<USAGE;

      Usage : $0 <Config File> <Link_A>
      Config file should contain the following properties with values ##>>>>>>>what kind of file is this config file, what is the content is it json or the same as mentioned here?

usergrp="";
skey="";
DBid="";
nt_id="";
team="";
feedurl="";
usr="";
pwd="";
category="";
dev="";
prio="";
USAGE
      print "$usage\n";
      exit ;
   }
