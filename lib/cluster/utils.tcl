namespace eval ::cluster::utils {
    # Encapsulates variables global to this namespace under their own
    # namespace, an idea originating from http://wiki.tcl.tk/1489.
    # Variables which name start with a dash are options and which
    # values can be changed to influence the behaviour of this
    # implementation.
    namespace eval vars {
        # Current verbosity level
        variable -verbose   NOTICE
        # Mapping from integer to string representation of verbosity levels
        variable verboseTags {1 FATAL 2 ERROR 3 WARN 4 NOTICE 5 INFO 6 DEBUG 7 TRACE}
        # File descriptor to dump log messages to
        variable -log       stderr
        # Date log output
        variable -date      "%Y%m%d %H%M%S"
        # Temporary directory, empty for good platform guess
        variable -tmp       ""
        # Characters to keep in temporary filepath
        variable fpathCharacters "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/-.,=_"
    }
    # Export all lower case procedure, arrange to be able to access
    # commands from the parent (cluster) namespace from here and
    # create an ensemble command called swarmmode (note the leading :: to make
    # this a top-level command!) to ease API calls.
    namespace export {[a-z]*}
    namespace path [namespace parent]
    namespace ensemble create -command ::utils
}


# ::cluster::tooling::defaults -- Set/get default parameters
#
#       This procedure takes an even list of keys and values used to
#       set the values of the options supported by the library.  The
#       list of options is composed of all variables starting with a
#       dash in the vars sub-namespace.  In the list, the dash
#       preceding the key is optional.
#
# Arguments:
#        args        List of key and values to set for module options.
#
# Results:
#       A dictionary with all current keys and their values
#
# Side Effects:
#       None.
proc ::cluster::utils::defaults { ns {args {}}} {
    set store ::[string trim $ns :]::vars
    foreach {k v} $args {
        set k -[string trimleft $k -]
        if { [info exists ${store}::$k] } {
            set ${store}::$k $v
        }
    }
        
    set state {}
    foreach v [info vars ${store}::-*] {
        lappend state [lindex [split $v ":"] end] [set $v]
    }
    return $state
}


# ::cluster::getopt -- Quick and Dirty Options Parser
#
#       Parses options, code comes from wiki.  Once parsed, an option
#       (and its argument) are removed from the argument list.
#
# Arguments:
#        _argv        List of arguments to parse
#        name        Name of option to look for.
#        _var        Pointer to variable in which to store value
#        dft        Default value if not found
#
# Results:
#       1 if option was found, 0 otherwise.
#
# Side Effects:
#       Modifies the incoming arguments list.
proc ::cluster::utils::getopt {_argv name {_var ""} {dft ""}} {
    upvar $_argv argv $_var var
    set pos [lsearch -regexp $argv ^$name]
    if {$pos>=0} {
        set to $pos
        if {$_var ne ""} {
            set var [lindex $argv [incr to]]
        }
        set argv [lreplace $argv $pos $to]
        return 1
    } else {
        # Did we provide a value to default?
        if {[llength [info level 0]] == 5} {set var $dft}
        return 0
    }
}


# ::cluster::utils::log -- Conditional logging
#
#       Conditionally output the message passed as an argument
#       depending on the current module debug level.  The level can
#       either be an integer or one of FATAL ERROR WARN NOTICE INFO
#       DEBUG, where FATAL corresponds to level 1 and DEBUG to
#       level 6.  Level 0 will therefor turn off ALL debugging.
#       Logging happens on the standard error, but this can be changed
#       through the -log option to the module.  Logging is pretty
#       printed using ANSI codes when the destination channel is a
#       terminal.
#
# Arguments:
#        lvl        Logging level of the message
#        msg        String content of the message.
#
# Results:
#       None.
#
# Side Effects:
#       Output message to logging channel whenever at the proper level.
proc ::cluster::utils::log { lvl msg } {
    # If we should output (i.e. level of message is below the global
    # module level), pretty print and output.
    if { [outlog $lvl l] } {
        set toTTY [dict exists [fconfigure ${vars::-log}] -mode]
        # Output the whole line.
        if { $toTTY } {
            puts ${vars::-log} [LogTerminal $l $msg]
        } else {
            puts ${vars::-log} [LogStandard $l $msg]
        }
    }
}


proc ::cluster::utils::outlog { { lvl "" } { intlvl_ ""} } {
    # Convert current module level from string to integer.
    set current [LogLevel ${vars::-verbose}]
    
    # Either return current log level or if we should log.
    if { $lvl eq "" } {
        return $current
    } else {
        if { $intlvl_ ne "" } {
            upvar $intlvl_ intlvl
        }
        # Convert incoming level from string to integer.
        set intlvl [LogLevel $lvl]
        return [expr {$current >= $intlvl}]
    }
    return -1
}


# ::cluster::utils::dget -- get or default from dictionary
#
#       Get the value of a key from a dictionary, returning a default value if
#       the key does not exist in the dictionary.
#
# Arguments:
#       d       Dictionary to get from
#       key     Key in dictionary to query
#       default	Default value to return when key does not exist
#
# Results:
#       Value of key in dictionary, or default value if it does not exist.
#
# Side Effects:
#       Copy the file using scp
proc ::cluster::utils::dget { d key { default "" } } {
    if { [dict exists $d $key] } {
        return [dict get $d $key]
    }
    return $default
}



# ::cluster::Temporary -- Temporary name
#
#       Generate a rather unique temporary name (to be used, for
#       example, when creating temporary files). The procedure only keep
#       worthwhile characters, trying to ensure minimal problems when it comes
#       to file paths.
#
# Arguments:
#        pfx        Prefix before unicity taggers
#
# Results:
#       A string that is made unique through the process identifier
#       and some randomness.
#
# Side Effects:
#       None.
proc ::cluster::utils::temporary { pfx } {
    set dirname [file dirname $pfx]
    set fname [file tail $pfx]
    
    set nm ""
    set allowed [split $vars::fpathCharacters ""]
    foreach c [split $fname ""] {
        if { [lsearch $allowed $c] >= 0 } {
            append nm $c
        } else {
            append nm "-"
        }
    }
    if { $dirname eq "." || $dirname eq "" } {
        return ${nm}-[pid]-[expr {int(rand()*1000)}]
    } else {
        return [file join $dirname ${nm}-[pid]-[expr {int(rand()*1000)}]]
    }
}


proc ::cluster::utils::tmpdir {} {
    if { ${vars::-tmp} ne "" } {
        return ${vars::-tmp}
    }
    
    if { [lsearch [split [::platform::generic] -] win32] >= 0 } {
        set resolutions [list USERPROFILE AppData/Local/Temp \
                windir TEMP \
                SystemRoot TEMP \
                TEMP "" TMP "" \
                "" "C:/TEMP" "" "C:/TMP" "" "C:/"]
    } else {
        set resolutions [list TMP "" "" /tmp]
    }
    
    foreach { var subdir }  $resolutions {
        set dir ""
        if { $var eq "" } {
            set dir $subdir
        } elseif { [info exists ::env($var)] && [set ::env($var)] ne "" } {
            set dir [file join [set ::env($var)] $subdir]
        }
        if { $dir ne "" && [file isdirectory $dir] } {
            log TRACE "Using $dir as a temporary directory"
            return $dir
        }
    }
    
    return [cwd]
}


proc ::cluster::utils::tmpfile { pfx ext } {
    return [temporary [file join [tmpdir] $pfx].[string trimleft $ext .]]
}



# ::cluster::Convert -- SI multiples converter
#
#       This procedure will convert sizes (memory or disk) to a target
#       unit.  The incoming size specification is either a floating
#       point (see below for value) or a floating point followed by a
#       unit specifier, e.g. 10k to express 10 kilobytes.  The unit
#       specifier is case independent and the conversion will
#       understand both k, kB or KB.  Recognised are multipliers up to
#       yottabyte, e.g. the leading letters (in order!): b (bytes), k,
#       m, g, t, p, e, z, y.  When the incoming size, its default unit
#       can be specified, in which case this is one of the unit string
#       as described before.  If a returning unit is specified, then it
#       is a unit string as described before and describes the unit of
#       the returned value.
#
# Arguments:
#	spec	Size specification, e.g. 1345, 34k or 20MB.
#	dft	Default Unit of size spec when unspecified, e.g. k, GB, etc.
#	unit	Unit of converted returned value, e.g. k, GB or similar.
#
# Results:
#       The converted value in the requested SI unit, or an error.
#
# Side Effects:
#       None.
proc ::cluster::utils::convert { spec {dft ""} { unit "" } { precision "%.01f"} } {
    # Extract value and first letter of unit specification from
    # string.
    set len [scan $spec "%f %c" val ustart]
    
    # Convert incoming string to number of bytes in metric format,
    # see: http://en.wikipedia.org/wiki/Gigabyte
    if { $len == 2 } {
        set i [string first [format %c $ustart] $spec]
        set m [Multiplier [string range $spec $i end]]
        set val [expr {$val*$m}]
    } else {
        if { $dft ne "" } {
            set m [Multiplier $dft]
            set val [expr {$val*$m}]
        }
    }
    
    # Now convert back to the requested size
    if { $unit ne "" } {
        set m [Multiplier $unit]
        set val [expr {$val/$m}]
    }
    if { [string match "*.0" $val] } {
        return [expr {int($val)}]
    }
    return [format $precision $val]
}



####################################################################
#
# Procedures below are internal to the implementation, they shouldn't
# be changed unless you wish to help...
#
####################################################################

# ::cluster::LogLevel -- Convert log levels
#
#       For convenience, log levels can also be expressed using
#       human-readable strings.  This procedure will convert from this
#       format to the internal integer format.
#
# Arguments:
#        lvl        Log level (integer or string).
#
# Results:
#       Log level in integer format, -1 if it could not be converted.
#
# Side Effects:
#       None.
proc ::cluster::utils::LogLevel { lvl } {
    if { ![string is integer $lvl] } {
        foreach {l str} $vars::verboseTags {
            if { [string match -nocase $str $lvl] } {
                return $l
            }
        }
        return -1
    }
    return $lvl
}


# ::cluster::+ -- Implements ANSI colouring codes.
#
#       Output ANSI colouring codes, inspired by wiki code at
#       http://wiki.tcl.tk/1143.
#
# Arguments:
#        args        List of colouring and effects to apply
#
# Results:
#       Return coding escape.
#
# Side Effects:
#       None.
proc ::cluster::utils::+ { args } {
    set map {
        normal 0 bold 1 light 2 blink 5 invert 7
        black 30 red 31 green 32 yellow 33 blue 34 purple 35 cyan 36 white 37
        Black 40 Red 41 Green 42 Yellow 43 Blue 44 Purple 45 Cyan 46 White 47
    }
    set t 0
    foreach i $args {
        set ix [lsearch -exact $map $i]
        if {$ix>-1} {lappend t [lindex $map [incr ix]]}
    }
    return "\033\[[join $t {;}]m"
}


# ::cluster::LogTerminal -- Create log line for terminal output
#
#       Pretty print a log message for output on the terminal.  This
#       will use ANSI colour codings to improve readability (and will
#       omit the timestamps).
#
# Arguments:
#        lvl     Log level (an integer)
#        msg     Log message
#
# Results:
#       Line to output on terminal
#
# Side Effects:
#       None.
proc ::cluster::utils::LogTerminal { lvl msg } {
    # Format the tagger so that they all have the same size,
    # i.e. the size of the longest level (in words)
    array set TAGGER $vars::verboseTags
    if { [info exists TAGGER($lvl)] } {
        set lbl [format %.6s "$TAGGER($lvl)        "]
    } else {
        set lbl [format %.6s "$lvl        "]
    }
    # Start by appending a human-readable level, using colors to
    # rank the levels. (see the + procedure below)
    set line "\["
    array set LABELER { 3 yellow 2 red 1 purple 4 blue 6 light }
    if { [info exists LABELER($lvl)] } {
        append line [+ $LABELER($lvl)]$lbl[+ normal]
    } else {
        append line $lbl
    }
    append line "\] "
    # Append the message itself, colorised again
    array set COLORISER { 3 yellow 2 red 1 purple 4 bold 6 light }
    if { [info exists COLORISER($lvl)] } {
        append line [+ $COLORISER($lvl)]$msg[+ normal]
    } else {
        append line $msg
    }
    
    return $line
}


# ::cluster::LogTerminal -- Create log line for file output
#
#       Pretty print a log message for output to a file descriptor.
#       This will add a timestamp to ease future introspection.
#
# Arguments:
#        lvl        Log level (an integer)
#        msg     Log message
#
# Results:
#       Line to output on file
#
# Side Effects:
#       None.
proc ::cluster::utils::LogStandard { lvl msg } {
    array set TAGGER $vars::verboseTags
    if { [info exists TAGGER($lvl)] } {
        set lbl $TAGGER($lvl)
    } else {
        set lbl $lvl
    }
    set dt [clock format [clock seconds] -format ${vars::-date}]
    return "\[$dt\] \[$lbl\] $msg"
}


proc ::cluster::utils::Multiplier { unit } {
    foreach {rx m} $vars::converters {
        if { [regexp -nocase -- $rx $unit] } {
            return $m
        }
    }
    
    return -code error "$unit is not a recognised multiple of bytes"
}



package provide cluster::utils 0.1
