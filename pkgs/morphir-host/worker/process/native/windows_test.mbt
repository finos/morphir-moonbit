// Windows tests. The command-line tests run everywhere; the job object test
// is in windows_wbtest.mbt.

///|
test "a Windows command line keeps empty arguments, quotes and backslashes" {
  assert_eq(
    @native.windows_command_line("C:\\work\\bin\\worker.exe", [
      "", "a b", "say \"hi\"", "trailing\\", "C:\\dir\\", "--",
    ]),
    "\"C:\\work\\bin\\worker.exe\" \"\" \"a b\" \"say \\\"hi\\\"\" \"trailing\\\\\" \"C:\\dir\\\\\" \"--\"",
  )
  assert_eq(
    @native.windows_command_line("w.exe", ["a\\\\\"b"]),
    "\"w.exe\" \"a\\\\\\\\\\\"b\"",
  )
}
