--  This file is covered by the Internet Software Consortium (ISC) License
--  Reference: ../License.txt

with Definitions; use Definitions;
with Ada.Text_IO;
with Ada.Characters.Latin_1;

package body Port_Specification is

   package TIO renames Ada.Text_IO;
   package LAT renames Ada.Characters.Latin_1;

   --------------------------------------------------------------------------------------------
   --  initialize
   --------------------------------------------------------------------------------------------
   procedure initialize (specs : out Portspecs) is
   begin
      specs.namebase := HT.blank;
      specs.version  := HT.blank;
      specs.revision := 0;
      specs.epoch    := 0;
      specs.keywords.Clear;
      specs.variants.Clear;

      specs.last_set := so_initialized;
   end initialize;


   --------------------------------------------------------------------------------------------
   --  set_single_string
   --------------------------------------------------------------------------------------------
   procedure set_single_string
     (specs : in out Portspecs;
      field : spec_field;
      value : String) is
   begin
      if HT.contains (S => value, fragment => " ") then
         raise contains_spaces;
      end if;
      case field is
         when sp_namebase =>
            if specs.last_set /= so_initialized then
               raise misordered with field'Img;
            end if;
            specs.namebase := HT.SUS (value);
            specs.last_set := so_namebase;
         when sp_version =>
            if specs.last_set /= so_namebase then
               raise misordered with field'Img;
            end if;
            specs.version := HT.SUS (value);
            specs.last_set := so_version;
         when others =>
            raise wrong_type with field'Img;
      end case;

   end set_single_string;


   --------------------------------------------------------------------------------------------
   --  append_list
   --------------------------------------------------------------------------------------------
   procedure append_list
     (specs : in out Portspecs;
      field : spec_field;
      value : String)
   is
      text_value : HT.Text := HT.SUS (value);
   begin
      if HT.contains (S => value, fragment => " ") then
         raise contains_spaces;
      end if;
      case field is
         when sp_keywords =>
            if specs.last_set /= so_keywords and then
              specs.last_set /= so_epoch and then
              specs.last_set /= so_revision and then
              specs.last_set /= so_version
            then
               raise misordered with field'Img;
            end if;
            if not keyword_is_valid (value) then
               raise wrong_value with "Keyword '" & value & "' is not recognized";
            end if;
            specs.keywords.Append (text_value);
            specs.last_set := so_keywords;
         when sp_variants =>
            if specs.last_set /= so_variants and then
              specs.last_set /= so_keywords
            then
               raise misordered with field'Img;
            end if;
            if specs.variants.Is_Empty and then
              value /= variant_standard
            then
               raise wrong_value with "First variant must be '" & variant_standard & "'";
            end if;
            if value'Length > 15 then
               raise wrong_value with "'" & value & "' value is too long (15-char limit)";
            end if;
            specs.variants.Append (text_value);
            specs.last_set := so_variants;
         when sp_contacts =>
            if specs.last_set /= so_contacts and then
              specs.last_set /= so_taglines
            then
               raise misordered with field'Img;
            end if;
            if not specs.all_taglines_defined then
               raise wrong_value with "Every variant must have SDESC definition.";
            end if;
            if not specs.contacts.Is_Empty then
               if specs.contacts.Contains (HT.SUS (contact_nobody)) then
                  raise wrong_value with "contact '" & contact_nobody & "' must be solitary";
               end if;
                if specs.contacts.Contains (HT.SUS (contact_automaton)) then
                  raise wrong_value with "contact '" & contact_automaton & "' must be solitary";
               end if;
               if value = contact_nobody or else value = contact_automaton then
                  raise wrong_value with "contact '" & value & "' must be solitary";
               end if;
            end if;
            if value /= contact_nobody and then
              value /= contact_automaton and then
              not (HT.contains (value, "_") and then
                   HT.contains (value, "[") and then
                   HT.contains (value, "@") and then
                   HT.contains (value, "]") and then
                  value (value'Last) = LAT.Right_Square_Bracket)
            then
               raise wrong_value with "incorrect contact format of '" & value & "'";
            end if;
            specs.contacts.Append (text_value);
            specs.last_set := so_contacts;
         when others =>
            raise wrong_type with field'Img;
      end case;

   end append_list;


   --------------------------------------------------------------------------------------------
   --  append_array
   --------------------------------------------------------------------------------------------
   procedure append_array
     (specs : in out Portspecs;
      field : spec_field;
      key   : String;
      value : String;
      allow_spaces : Boolean)
   is
      text_key   : HT.Text := HT.SUS (key);
      text_value : HT.Text := HT.SUS (value);
   begin
      if not allow_spaces and then
        HT.contains (S => value, fragment => " ")
      then
         raise contains_spaces;
      end if;
      case field is
         when sp_taglines =>
            if specs.last_set /= so_taglines and then
              specs.last_set /= so_variants
            then
               raise misordered with field'Img;
            end if;
            if specs.taglines.Contains (text_key) then
               raise dupe_spec_key with key & " (SDESC)";
            end if;
            --  SDESC requirements checked by caller.  Assume string is legal.
            specs.taglines.Insert (Key      => text_key,
                                   New_Item => text_value);
            specs.last_set := so_taglines;
         when others =>
            raise wrong_type with field'Img;
      end case;
   end append_array;


   --------------------------------------------------------------------------------------------
   --  set_natural_integer
   --------------------------------------------------------------------------------------------
   procedure set_natural_integer
     (specs : in out Portspecs;
      field : spec_field;
      value : Natural) is
   begin
      case field is
         when sp_revision =>
            if specs.last_set /= so_version then
               raise misordered with field'Img;
            end if;
            specs.revision := value;
            specs.last_set := so_revision;
         when sp_epoch =>
            if specs.last_set /= so_revision and then
              specs.last_set /= so_version
            then
               raise misordered with field'Img;
            end if;
            specs.epoch := value;
            specs.last_set := so_epoch;
         when others =>
            raise wrong_type with field'Img;
      end case;
   end set_natural_integer;


   --------------------------------------------------------------------------------------------
   --  variant_exists
   --------------------------------------------------------------------------------------------
   function variant_exists (specs : Portspecs; variant : String) return Boolean
   is
   begin
      return specs.variants.Contains (Item => HT.SUS (variant));
   end variant_exists;


   --------------------------------------------------------------------------------------------
   --  all_taglines_defined
   --------------------------------------------------------------------------------------------
   function all_taglines_defined (specs : Portspecs) return Boolean
   is
      procedure check (position : string_crate.Cursor);

      all_present : Boolean := True;

      procedure check (position : string_crate.Cursor)
      is
         variant : HT.Text := string_crate.Element (position);
      begin
         if not specs.taglines.Contains (variant) then
            all_present := False;
         end if;
      end check;
   begin
      specs.variants.Iterate (Process => check'Access);
      return all_present;
   end all_taglines_defined;


   --------------------------------------------------------------------------------------------
   --  keyword_is_valid
   --------------------------------------------------------------------------------------------
   function keyword_is_valid (keyword : String) return Boolean is
   begin
      return (keyword = "accessibility" or else
              keyword = "archivers" or else
              keyword = "astro" or else
              keyword = "audio" or else
              keyword = "benchmarks" or else
              keyword = "biology" or else
              keyword = "cad" or else
              keyword = "comms" or else
              keyword = "converters" or else
              keyword = "databases" or else
              keyword = "deskutils" or else
              keyword = "devel" or else
              keyword = "dns" or else
              keyword = "editors" or else
              keyword = "emulators" or else
              keyword = "finance" or else
              keyword = "ftp" or else
              keyword = "games" or else
              keyword = "graphics" or else
              keyword = "irc" or else
              keyword = "lang" or else
              keyword = "mail" or else
              keyword = "math" or else
              keyword = "misc" or else
              keyword = "multimedia" or else
              keyword = "net" or else
              keyword = "net_im" or else
              keyword = "net_mgmt" or else
              keyword = "net_p2p" or else
              keyword = "news" or else
              keyword = "print" or else
              keyword = "raven" or else
              keyword = "science" or else
              keyword = "security" or else
              keyword = "shells" or else
              keyword = "sysutils" or else
              keyword = "textproc" or else
              keyword = "www" or else
              keyword = "x11" or else
              keyword = "x11_clocks" or else
              keyword = "x11_drivers" or else
              keyword = "x11_fm" or else
              keyword = "x11_fonts" or else
              keyword = "x11_servers" or else
              keyword = "x11_toolkits" or else
              keyword = "x11_wm" or else
              keyword = "ada" or else
              keyword = "c++" or else
              keyword = "csharp" or else
              keyword = "java" or else
              keyword = "javascript" or else
              keyword = "lisp" or else
              keyword = "perl" or else
              keyword = "php" or else
              keyword = "python" or else
              keyword = "ruby" or else
              keyword = "scheme" or else
              keyword = "Arabic" or else
              keyword = "Chinese" or else
              keyword = "French" or else
              keyword = "German" or else
              keyword = "Italian" or else
              keyword = "Japanese" or else
              keyword = "Russian" or else
              keyword = "Spanish" or else
              keyword = "Vietnamese");
   end keyword_is_valid;


   --------------------------------------------------------------------------------------------
   --  dump_specification
   --------------------------------------------------------------------------------------------
   procedure dump_specification (specs : Portspecs)
   is
      procedure print_item (position : string_crate.Cursor);
      procedure print_item (position : def_crate.Cursor);

      array_label : Positive;

      procedure print_item (position : string_crate.Cursor)
      is
         index : Natural := string_crate.To_Index (position);
      begin
         if index > 1 then
            TIO.Put (" ");
         end if;
         TIO.Put (HT.USS (string_crate.Element (position)));
      end print_item;

      procedure print_item (position : def_crate.Cursor) is
      begin
         case array_label is
            when 1 => TIO.Put ("SDESC[");
            when others => null;
         end case;
         TIO.Put_Line (HT.USS (def_crate.Key (position)) & LAT.Right_Square_Bracket &
                         LAT.HT & LAT.HT & HT.USS (def_crate.Element (position)));
      end print_item;
   begin
      TIO.Put_Line ("NAMEBASE=" & LAT.HT & LAT.HT & HT.USS (specs.namebase));
      TIO.Put_Line ("VERSION="  & LAT.HT & LAT.HT & HT.USS (specs.version));
      TIO.Put_Line ("REVISION=" & LAT.HT & LAT.HT & HT.int2str (specs.revision));
      TIO.Put_Line ("EPOCH="    & LAT.HT & LAT.HT & LAT.HT & HT.int2str (specs.epoch));
      TIO.Put      ("KEYWORDS=" & LAT.HT & LAT.HT);
      specs.keywords.Iterate (Process => print_item'Access);
      TIO.Put      (LAT.LF);
      TIO.Put      ("VARIANTS=" & LAT.HT & LAT.HT);
      specs.variants.Iterate (Process => print_item'Access);
      TIO.Put      (LAT.LF);
      array_label := 1;
      specs.taglines.Iterate (Process => print_item'Access);
      TIO.Put      ("CONTACTS=" & LAT.HT & LAT.HT);
      specs.contacts.Iterate (Process => print_item'Access);
      TIO.Put      (LAT.LF);
   end dump_specification;

end Port_Specification;
