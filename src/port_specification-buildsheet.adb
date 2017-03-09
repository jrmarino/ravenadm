--  This file is covered by the Internet Software Consortium (ISC) License
--  Reference: ../License.txt

with Ada.Characters.Latin_1;
with Ada.Directories;
with Ada.Text_IO;
with File_Operations;

package body Port_Specification.Buildsheet is

   package TIO renames Ada.Text_IO;
   package DIR renames Ada.Directories;
   package LAT renames Ada.Characters.Latin_1;
   package FOP renames File_Operations;

   --------------------------------------------------------------------------------------------
   --  generator
   --------------------------------------------------------------------------------------------
   procedure generator
     (specs       : Portspecs;
      ravensrcdir : String;
      output_file : String)
   is
      procedure send (data : String; use_put : Boolean := False);
      procedure send (varname : String; value, default : Integer);
      procedure send (varname, value : String);
      procedure send (varname : String; value : HT.Text);
      procedure send (varname : String; crate : string_crate.Vector; flavor : Positive);
      procedure send (varname : String; crate : def_crate.Map);
      procedure send (varname : String; crate : list_crate.Map);
      procedure send (varname : String; value : Boolean; dummy : Boolean);
      procedure send_options;
      procedure send_targets;
      procedure send_descriptions;
      procedure print_item     (position : string_crate.Cursor);
      procedure print_item40   (position : string_crate.Cursor);
      procedure print_straight (position : string_crate.Cursor);
      procedure print_adjacent (position : string_crate.Cursor);
      procedure dump_vardesc   (position : string_crate.Cursor);
      procedure dump_vardesc2  (position : string_crate.Cursor);
      procedure dump_sdesc     (position : def_crate.Cursor);
      procedure dump_sites     (position : list_crate.Cursor);
      procedure dump_distfiles (position : string_crate.Cursor);
      procedure dump_targets   (position : list_crate.Cursor);
      procedure dump_helper (option_name : String; crate : string_crate.Vector; helper : String);
      procedure expand_option_record (position : option_crate.Cursor);
      procedure blank_line;
      procedure send_file      (filename : String);

      write_to_file   : constant Boolean := (output_file /= "");
      makefile_handle : TIO.File_Type;
      varname_prefix  : HT.Text;
      current_len     : Natural;
      currently_blank : Boolean := True;
      desc_prefix     : constant String := "descriptions/desc.";
      temp_storage    : string_crate.Vector;

      procedure send (data : String;  use_put : Boolean := False) is
      begin
         if write_to_file then
            if use_put then
               TIO.Put (makefile_handle, data);
            else
               TIO.Put_Line (makefile_handle, data);
            end if;
         else
            if use_put then
               TIO.Put (data);
            else
               TIO.Put_Line (data);
            end if;
         end if;
         if data /= "" then
            currently_blank := False;
         end if;
      end send;

      procedure send (varname, value : String) is
      begin
         if value /= "" then
            send (align24 (varname & LAT.Equals_Sign) & value);
         end if;
      end send;

      procedure send (varname : String; value : HT.Text) is
      begin
         if not HT.IsBlank (value) then
            send (align24 (varname & LAT.Equals_Sign) & HT.USS (value));
         end if;
      end send;

      procedure send (varname : String; value, default : Integer) is
      begin
         if value /= default then
            send (align24 (varname & LAT.Equals_Sign) & HT.int2str (value));
         end if;
      end send;

      procedure send (varname : String; crate : string_crate.Vector; flavor : Positive) is
      begin
         if crate.Is_Empty then
            return;
         end if;
         case flavor is
            when 1 =>
               send (align24 (varname & "="), True);
               crate.Iterate (Process => print_item'Access);
            when 2 =>
               current_len := 0;
               send (align24 (varname & "="), True);
               crate.Iterate (Process => print_adjacent'Access);
               send ("");
            when 3 =>
               varname_prefix := HT.SUS (varname);
               crate.Iterate (Process => dump_distfiles'Access);
            when others =>
               null;
         end case;
      end send;

      procedure send (varname : String; crate : def_crate.Map) is
      begin
         varname_prefix := HT.SUS (varname);
         crate.Iterate (Process => dump_sdesc'Access);
      end send;

      procedure send (varname : String; crate : list_crate.Map) is
      begin
         varname_prefix := HT.SUS (varname);
         crate.Iterate (Process => dump_sites'Access);
      end send;

      procedure send (varname : String; value : Boolean; dummy : Boolean) is
      begin
         if value then
            send (align24 (varname & LAT.Equals_Sign) & "yes");
         end if;
      end send;

      procedure print_item (position : string_crate.Cursor)
      is
         index : Natural := string_crate.To_Index (position);
         item  : String  := HT.USS (string_crate.Element (position));
      begin
         if index = 1 then
            send (item);
         else
            send (LAT.HT & LAT.HT & LAT.HT & item);
         end if;
      end print_item;

      procedure print_item40 (position : string_crate.Cursor)
      is
         index : Natural := string_crate.To_Index (position);
         item  : String  := HT.USS (string_crate.Element (position));
      begin
         if index = 1 then
            send (item);
         else
            send (LAT.HT & LAT.HT & LAT.HT & LAT.HT & LAT.HT & item);
         end if;
      end print_item40;

      procedure print_adjacent (position : string_crate.Cursor)
      is
         index : Natural := string_crate.To_Index (position);
         item  : String  := HT.USS (string_crate.Element (position));
         len   : Natural := item'Length;
      begin
         if current_len + len + 1 > 76 then
            current_len := 0;
            send ("");
         end if;
         if current_len > 0 then
            send (" ", True);
            current_len := current_len + 1;
         end if;
         send (item, True);
         current_len := current_len + len;
      end print_adjacent;

      procedure print_straight (position : string_crate.Cursor)
      is
         item  : String  := HT.USS (string_crate.Element (position));
      begin
         send (item);
      end print_straight;

      procedure dump_sdesc (position : def_crate.Cursor)
      is
         varname : String := HT.USS (varname_prefix)  & LAT.Left_Square_Bracket &
                   HT.USS (def_crate.Key (position)) & LAT.Right_Square_Bracket & LAT.Equals_Sign;
      begin
         send (align24 (varname) & HT.USS (def_crate.Element (position)));
      end dump_sdesc;

      procedure dump_sites (position : list_crate.Cursor)
      is
         rec     : group_list renames list_crate.Element (position);
         varname : String := HT.USS (varname_prefix)  & LAT.Left_Square_Bracket &
                   HT.USS (rec.group) & LAT.Right_Square_Bracket & LAT.Equals_Sign;
      begin
         if not rec.list.Is_Empty then
            send (align24 (varname), True);
            rec.list.Iterate (Process => print_item'Access);
         end if;
      end dump_sites;

      procedure dump_distfiles (position : string_crate.Cursor)
      is
         index : Natural := string_crate.To_Index (position);
         NDX   : String  := HT.USS (varname_prefix)  & LAT.Left_Square_Bracket &
           HT.int2str (index) & LAT.Right_Square_Bracket & LAT.Equals_Sign;
      begin
         send (align24 (NDX) & HT.USS (string_crate.Element (position)));
      end dump_distfiles;

      procedure blank_line is
      begin
         if not currently_blank then
            send ("");
         end if;
         currently_blank := True;
      end blank_line;

      procedure send_targets is
      begin
         specs.make_targets.Iterate (Process => dump_targets'Access);
      end send_targets;

      procedure dump_targets (position : list_crate.Cursor)
      is
         rec    : group_list renames list_crate.Element (position);
         target : String := HT.USS (rec.group) & LAT.Colon;
      begin
         blank_line;
         send (target);
         rec.list.Iterate (Process => print_straight'Access);
      end dump_targets;

      procedure dump_helper (option_name : String; crate : string_crate.Vector; helper : String)
      is
      begin
         if not crate.Is_Empty then
            send (align40 (LAT.Left_Square_Bracket & option_name & "]." &
                    helper & LAT.Equals_Sign), True);
            crate.Iterate (Process => print_item40'Access);
         end if;
      end dump_helper;

      procedure expand_option_record (position : option_crate.Cursor)
      is
         rec  : Option_Helper renames option_crate.Element (position);
         name : String := HT.USS (rec.option_name);
      begin
         blank_line;
         if not HT.IsBlank (rec.BROKEN_ON) then
            send (align40 (LAT.Left_Square_Bracket & name & "].BROKEN_ON=") &
                    HT.USS (rec.BROKEN_ON));
         end if;
         dump_helper (name, rec.BUILD_DEPENDS_ON, "BUILD_DEPENDS_ON");
         dump_helper (name, rec.BUILD_TARGET_ON, "BUILD_TARGET_ON");
         dump_helper (name, rec.CFLAGS_ON, "CFLAGS_ON");
         dump_helper (name, rec.CMAKE_ARGS_OFF, "CMAKE_ARGS_OFF");
         dump_helper (name, rec.CMAKE_ARGS_ON, "CMAKE_ARGS_ON");
         dump_helper (name, rec.CMAKE_BOOL_T_BOTH, "CMAKE_BOOL_T_BOTH");
         dump_helper (name, rec.CMAKE_BOOL_F_BOTH, "CMAKE_BOOL_F_BOTH");
         dump_helper (name, rec.CONFIGURE_ARGS_ON, "CONFIGURE_ARGS_ON");
         dump_helper (name, rec.CONFIGURE_ARGS_OFF, "CONFIGURE_ARGS_OFF");
         dump_helper (name, rec.CONFIGURE_ENABLE_BOTH, "CONFIGURE_ENABLE_BOTH");
         dump_helper (name, rec.CONFIGURE_ENV_ON, "CONFIGURE_ENV_ON");
         dump_helper (name, rec.CONFIGURE_WITH_BOTH, "CONFIGURE_WITH_BOTH");
         dump_helper (name, rec.CPPFLAGS_ON, "CPPFLAGS_ON");
         dump_helper (name, rec.CXXFLAGS_ON, "CXXFLAGS_ON");
         dump_helper (name, rec.DF_INDEX_ON, "DF_INDEX_ON");
         dump_helper (name, rec.EXTRA_PATCHES_ON, "EXTRA_PATCHES_ON");
         dump_helper (name, rec.EXTRACT_ONLY_ON, "EXTRACT_ONLY_ON");
         dump_helper (name, rec.GH_ACCOUNT_ON, "GH_ACCOUNT_ON");
         dump_helper (name, rec.GH_PROJECT_ON, "GH_PROJECT_ON");
         dump_helper (name, rec.GH_SUBDIR_ON, "GH_SUBDIR_ON");
         dump_helper (name, rec.GH_TAGNAME_ON, "GH_TAGNAME_ON");
         dump_helper (name, rec.GH_TUPLE_ON, "GH_TUPLE_ON");
         dump_helper (name, rec.IMPLIES_ON, "IMPLIES_ON");
         dump_helper (name, rec.INFO_ON, "INFO_ON");
         dump_helper (name, rec.INSTALL_TARGET_ON, "INSTALL_TARGET_ON");
         dump_helper (name, rec.KEYWORDS_ON, "KEYWORDS_ON");
         dump_helper (name, rec.LDFLAGS_ON, "LDFLAGS_ON");
         dump_helper (name, rec.LIB_DEPENDS_ON, "LIB_DEPENDS_ON");
         dump_helper (name, rec.MAKE_ARGS_ON, "MAKE_ARGS_ON");
         dump_helper (name, rec.MAKE_ENV_ON, "MAKE_ENV_ON");
         dump_helper (name, rec.PATCHFILES_ON, "PATCHFILES_ON");
         dump_helper (name, rec.PLIST_SUB_ON, "PLIST_SUB_ON");
         dump_helper (name, rec.PREVENTS_ON, "PREVENTS_ON");
         dump_helper (name, rec.QMAKE_OFF, "QMAKE_OFF");
         dump_helper (name, rec.QMAKE_ON, "QMAKE_ON");
         dump_helper (name, rec.RUN_DEPENDS_ON, "RUN_DEPENDS_ON");
         dump_helper (name, rec.SUB_FILES_ON, "SUB_FILES_ON");
         dump_helper (name, rec.SUB_LIST_ON, "SUB_LIST_ON");
         dump_helper (name, rec.TEST_TARGET_ON, "TEST_TARGET_ON");
         dump_helper (name, rec.USES_ON, "USES_ON");
      end expand_option_record;

      procedure send_options is
      begin
         specs.ops_helpers.Iterate (Process => expand_option_record'Access);
      end send_options;

      procedure send_file (filename : String)
      is
         abspath : constant String := ravensrcdir & "/" & filename;
      begin
         if DIR.Exists (abspath) then
            declare
               contents : constant String := FOP.get_file_contents (abspath);
            begin
               blank_line;
               send ("[FILE:" & HT.int2str (contents'Length) & LAT.Colon & filename &
                       LAT.Right_Square_Bracket);
               send (contents);
            end;
         end if;
      end send_file;

      procedure dump_vardesc2  (position : string_crate.Cursor)
      is
         item : HT.Text renames string_crate.Element (position);
         subpkg : String := HT.USS (item);
      begin
         send_file (desc_prefix & subpkg & LAT.Full_Stop & HT.USS (varname_prefix));
         if DIR.Exists (ravensrcdir & "/" & desc_prefix & subpkg) and then
           not temp_storage.Contains (item)
         then
            temp_storage.Append (item);
            send_file (desc_prefix & subpkg);
         end if;
      end dump_vardesc2;

      procedure dump_vardesc (position : string_crate.Cursor)
      is
         variant : String := HT.USS (string_crate.Element (position));
      begin
         varname_prefix := string_crate.Element (position);
         specs.subpackages.Element (varname_prefix).list.Iterate (dump_vardesc2'Access);
      end dump_vardesc;

      procedure send_descriptions is
      begin
         specs.variants.Iterate (Process => dump_vardesc'Access);
         temp_storage.Clear;
      end send_descriptions;

   begin
      send ("# Buildsheet autogenerated by ravenadm tool -- Do not edit." & LAT.LF);

      send ("NAMEBASE",             specs.namebase);
      send ("VERSION",              specs.version);
      send ("REVISION",             specs.revision, 0);
      send ("EPOCH",                specs.epoch, 0);
      send ("KEYWORDS",             specs.keywords, 2);
      send ("VARIANTS",             specs.variants, 2);
      send ("SDESC",                specs.taglines);
      send ("HOMEPAGE",             specs.homepage);
      send ("CONTACT",              specs.contacts, 1);
      blank_line;

      --      send ("DOWNLOAD_GROUPS=", specs.d
      send ("SITES",                specs.dl_sites);
      send ("DISTFILE",             specs.distfiles, 3);
      send ("DIST_SUBDIR",          specs.dist_subdir);
      send ("DF_INDEX",             specs.df_index, 2);
      send ("SPKGS",                specs.subpackages);

      blank_line;
      send ("OPTIONS_AVAILABLE",    specs.ops_avail, 2);
      send ("OPTIONS_STANDARD",     specs.ops_standard, 2);
      send ("VOPTS",                specs.variantopts);
      send ("OPT_ON",               specs.options_on);
      blank_line;
      send ("BROKEN",               specs.broken);
      send ("NOT_FOR_OPSYS",        specs.exc_opsys, 2);
      send ("ONLY_FOR_OPSYS",       specs.inc_opsys, 2);
      send ("NOT_FOR_ARCH",         specs.exc_arch, 2);
      send ("DEPRECATED",           specs.deprecated);
      send ("EXPIRATION_DATE",      specs.expire_date);
      blank_line;
      send ("BUILD_DEPENDS",        specs.build_deps, 1);
      send ("LIB_DEPENDS",          specs.lib_deps, 1);
      send ("RUN_DEPENDS",          specs.run_deps, 1);
      send ("USES",                 specs.uses, 2);
      blank_line;
      send ("DISTNAME",             specs.distname);
      send ("DIRTY_EXTRACT",        specs.extract_lha, 2);
      send ("EXTRACT_ONLY",         specs.extract_only, 2);
      send ("EXTRACT_WITH_UNZIP",   specs.extract_zip, 2);
      send ("EXTRACT_WITH_7Z",      specs.extract_7z, 2);
      send ("EXTRACT_WITH_LHA",     specs.extract_lha, 2);
      send ("EXTRACT_HEAD",         specs.extract_head);
      send ("EXTRACT_TAIL",         specs.extract_tail);
      blank_line;
      send ("PATCH_WRKSRC",         specs.patch_wrksrc);
      send ("PATCHFILES",           specs.patchfiles, 1);
      send ("EXTRA_PATCHES",        specs.extra_patches, 1);
      send ("PATCH_STRIP",          specs.patch_strip, 2);
      send ("PATCHFILES_STRIP",     specs.patchfiles, 2);
      blank_line;
      send ("MUST_CONFIGURE",       specs.config_must);
      send ("GNU_CONFIGURE_PREFIX", specs.config_prefix);
      send ("CONFIGURE_OUTSOURCE",  specs.config_outsrc, True);
      send ("CONFIGURE_WRKSRC",     specs.config_wrksrc);
      send ("CONFIGURE_SCRIPT",     specs.config_script);
      send ("CONFIGURE_TARGET",     specs.config_target);
      send ("CONFIGURE_ARGS",       specs.config_args, 1);
      send ("CONFIGURE_ENV",        specs.config_env, 1);
      send ("APPLY_F10_FIX",        specs.apply_f10_fix, True);
      blank_line;
      send ("SKIP_BUILD",           specs.skip_build, True);
      send ("BUILD_WRKSRC",         specs.build_wrksrc);
      send ("BUILD_TARGET",         specs.build_target, 2);
      send ("MAKEFILE",             specs.makefile);
      send ("MAKE_ARGS",            specs.make_args, 1);
      send ("MAKE_ENV",             specs.make_env, 1);
      send ("DESTDIRNAME",          specs.destdirname);
      send ("DESTDIR_VIA_ENV",      specs.destdir_env, True);
      send ("SINGLE_JOB",           specs.single_job, True);
      blank_line;
      send ("SKIP_INSTALL",         specs.skip_install, True);
      send ("INSTALL_WRKSRC",       specs.install_wrksrc);
      send ("INSTALL_TARGET",       specs.install_tgt, 2);
      blank_line;
      send ("CFLAGS",               specs.cflags, 1);
      send ("CXXFLAGS",             specs.cxxflags, 1);
      send ("CPPFLAGS",             specs.cppflags, 1);
      send ("LDFLAGS",              specs.ldflags, 1);
      send ("OPTMIZER_LEVEL",       specs.optimizer_lvl, 2);

      --  TODO
      --  INFO_PATH (needs impl, doc)
      --  INFO (implemented wrong, needs to be array of spkg, doc)
      --  MANPREFIX[x] (needs imp, doc)
      --  RC_SUBR (array spkg), (needs imp, doc)
      --  CCACHE_BUILD=yes (needs imp, doc, fix README)
      --  CCACHE_DIR (needs imp, doc)
      --  SKIP_CCACHE=yes (needs imp, doc, fix README)
      --  All Github support
      --  WITH_DEBUG (?)
      --  DEBUG_FLAGS (?)

      send_options;
      send_targets;
      send_descriptions;

      if write_to_file then
         TIO.Close (makefile_handle);
      end if;
   exception
      when others =>
         if TIO.Is_Open (makefile_handle) then
            TIO.Close (makefile_handle);
         end if;

   end generator;


   --------------------------------------------------------------------------------------------
   --  align24
   --------------------------------------------------------------------------------------------
   function align24 (payload : String) return String
   is
      len : Natural := payload'Length;
   begin
      if len < 8 then
         return payload & LAT.HT & LAT.HT & LAT.HT;
      elsif len < 16 then
         return payload & LAT.HT & LAT.HT;
      elsif len < 24 then
         return payload & LAT.HT;
      else
         return payload;
      end if;
   end align24;


   --------------------------------------------------------------------------------------------
   --  align40
   --------------------------------------------------------------------------------------------
   function align40 (payload : String) return String
   is
      len : Natural := payload'Length;
   begin
      if len < 8 then
         return payload & LAT.HT & LAT.HT & LAT.HT & LAT.HT & LAT.HT;
      elsif len < 16 then
         return payload & LAT.HT & LAT.HT & LAT.HT & LAT.HT;
      elsif len < 24 then
         return payload & LAT.HT & LAT.HT & LAT.HT;
      elsif len < 32 then
         return payload & LAT.HT & LAT.HT;
      elsif len < 40 then
         return payload & LAT.HT;
      else
         return payload;
      end if;
   end align40;

end Port_Specification.Buildsheet;
