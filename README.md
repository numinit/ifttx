# ifttx

Like ifttt, but for amateur radio. "If fldigi's rx text matches something, do something else."

fldigi is notoriously hard to compose with other applications and doesn't follow the UNIX
philosophy. Patch it with nix and puppet it with a Ruby script to match regexes in the RX text
window and run a command when something matches.

Note that we need to generate a fresh home directory for fldigi for every launch,
so we stick one in tmpfs. fldigi also needs to reload after generating the initial config
and us adding our changes, so we start it a second time to actually perform the decoding.

## Running it

`nix run` ought to do the trick.

For example, to decode CW at frequency offset 1337, pass:
`-o mode_name=CW -o wf_carrier=1337 -o CWSWEETSPOT=1337 \
-o PORTINDEVICE='(name of input device)'`

To match a Github PR, do something like: `-r 'PR ?(\\d{6})'`

And if you want to run nixpkgs-review with the first match group, do:
`-c 'sh -c "cd ~/projects/nix/nixpkgs && nixpkgs-review pr $1"'`
