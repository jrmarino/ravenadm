--  This file is covered by the Internet Software Consortium (ISC) License
--  Reference: ../License.txt

with Definitions; use Definitions;

with Port_Specification;

private with HelperText;
private with Ada.Containers.Hashed_Maps;

package Specification_Parser is

   package PSP renames Port_Specification;

   --  Parse the port specification file and extract the data into the specification record.
   procedure parse_specification_file
     (dossier         : String;
      specification   : out PSP.Portspecs;
      success         : out Boolean;
      opsys_focus     : supported_opsys;
      arch_focus      : supported_arch;
      stop_at_targets : Boolean;
      extraction_dir  : String := "");

   --  If the parse procedure fails, this function returns the associated error message
   function get_parse_error return String;

private

   package HT  renames HelperText;
   package CON renames Ada.Containers;

   package def_crate is new CON.Hashed_Maps
        (Key_Type        => HT.Text,
         Element_Type    => HT.Text,
         Hash            => HT.hash,
         Equivalent_Keys => HT.equivalent,
         "="             => HT.SU."=");

   type spec_array   is (not_array, def, sdesc, sites, distfile, spkgs, vopts,
                         ext_head, ext_tail, option_on, broken);
   type spec_singlet is (not_singlet, namebase, version, revision, epoch, keywords, variants,
                         contacts, dl_groups, dist_subdir, df_index, opt_avail, opt_standard,
                         exc_opsys, inc_opsys, exc_arch, ext_only, ext_zip, ext_7z, ext_lha,
                         ext_dirty, distname, skip_build, single_job, destdir_env, build_wrksrc,
                         makefile, destdirname, make_args, make_env, build_target, cflags,
                         cxxflags, cppflags, ldflags, homepage, skip_install, opt_level,
                         patchfiles, uses, sub_list, sub_files, config_args, config_env,
                         build_deps, buildrun_deps, run_deps, cmake_args, qmake_args, info,
                         install_tgt, patch_wrksrc, patch_strip, patchfiles_strip, extra_patches,
                         must_configure, configure_wrksrc, configure_script, gnu_cfg_prefix,
                         configure_target, config_outsource, apply_10_fix, deprecated,
                         expiration, install_wrksrc, plist_sub, prefix, licenses, users, groups);

   type spec_target  is (not_target, target_title, target_body, bad_target);
   type type_category is (cat_none, cat_array, cat_singlet, cat_target, cat_option, cat_file);

   last_parse_error   : HT.Text;
   spec_definitions   : def_crate.Map;

   missing_definition : exception;
   bad_modifier       : exception;
   expansion_too_long : exception;
   mistabbed          : exception;
   mistabbed_40       : exception;
   integer_expected   : exception;
   extra_spaces       : exception;
   duplicate_key      : exception;
   generic_format     : exception;

   --  This looks for the pattern ${something}.  If not found, the original value is returned.
   --  Otherwise it looks up "something".  If that's not a definition, the missing_definition
   --  exception is thrown, otherwise it's expanded.  If the $something contains a modifier
   --  (column followed by code) and that modifier is unknown or misused, the bad_modifier
   --  exception is thrown.  Upon cycle, repeat until no more patterns found, then return
   --  final expanded value.  If the length of the expanded value exceeds 512 bytes, the
   --  expansion_too_long exception is thrown.
   function expand_value (value : String) return String;

   --  If the line represents a recognized array type, indicate which one,
   --  otherwise return "not_array"
   function determine_array (line : String) return spec_array;

   --  If the line represents a recognized singlet type, indicate which one,
   --  otherwise return "not_singlet"
   function determine_singlet (line : String) return spec_singlet;

   --  Returns "not_helper_format" if it's not in option format
   --  Returns "not_supported_helper" if it's not a recognized (supported) helper
   --  Otherwise it returns the detected spec_option
   function determine_option (line : String) return PSP.spec_option;

   --  Returns empty string if it's not a recognized option, otherwise it returns
   --  The option name.  If 5-tabs detected, return previous name (given).
   function extract_option_name
     (spec      : PSP.Portspecs;
      line      : String;
      last_name : HT.Text) return String;

   --  If the line represents the makefile target definition or it's following body,
   --  return which one, otherwise return "not_target".
   --  Exception: if formatted as a target def. which is not recognized, return "bad_target"
   function determine_target
     (spec      : PSP.Portspecs;
      line      : String;
      last_seen : type_category) return spec_target;

   --  Returns true if the given line indicates a package containing a file follows
   function is_file_capsule (line : String) return Boolean;

   --  Given a string validated as a file capsule, return the size of the file
   function retrieve_file_size (capsule_label : String) return Natural;

   --  Given a string validated as a file capsule, return the relative path for extracted file
   function retrieve_file_name (capsule_label : String) return String;

   --  Returns everything following the tab(s) until end of line.  If last tab doesn't align
   --  text with column 24, the mistabbed exception is thrown.
   function retrieve_single_value (line : String) return String;

   --  Returns everything following the tab(s) until end of line.  If last tab doesn't align
   --  text with column 40, the mistabbed exception is thrown.
   function retrieve_single_option_value (line : String) return String;

   --  Calls retrieve_single_value and tries to convert to a natural number.
   function retrieve_single_integer (line : String) return Natural;

   --  Returns the key for array item definition lines.
   function retrieve_key (line : String; previous_index : HT.Text) return HT.Text;

   --  Line may contain spaces, and each space is considered a single item on a list.
   --  This iterates through the value with space delimiters.
   procedure build_list (spec : in out PSP.Portspecs; field : PSP.spec_field; line : String);

   --  Same as build_list but for options.
   --  Handles all valid options (since only one isn't a list)
   procedure build_list
     (spec   : in out PSP.Portspecs;
      field  : PSP.spec_option;
      option : String;
      line   : String);

   --  Line may contain spaces and they are considered part of an entire string
   procedure build_string (spec : in out PSP.Portspecs; field : PSP.spec_field; line : String);

   --  For boolean variables, ensure "yes" was defined and pass to specification record.
   procedure set_boolean (spec : in out PSP.Portspecs; field : PSP.spec_field; line : String);

   --  Pass integer variables to specification record
   procedure set_natural (spec : in out PSP.Portspecs; field : PSP.spec_field; line : String);

   --  Line may contain spaces, and each space is considered a single item on a list.
   --  This iterates through the value with space delimiters to build a group list.
   procedure build_group_list
     (spec  : in out PSP.Portspecs;
      field : PSP.spec_field;
      key   : String;
      value : String);

   --  Return true if all final validity checks pass
   function late_validity_check_error (spec : PSP.Portspecs) return HT.Text;

   --  Returns new filename if it matches dynamic pkg-message filename, otherwise return blank
   function tranform_pkg_message (filename, match_opsys, match_arch : String) return String;

end Specification_Parser;
