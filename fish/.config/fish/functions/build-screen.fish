function build-screen --description "Watch build screen pipeline for a given account prefix (default cnops)"
    # Forwards the optional prefix arg. Supports:
    #   build-screen          (prefix defaults to cnops)
    #   build-screen cn-cx
    nu ~/overlays/build-screen.nu $argv
end
