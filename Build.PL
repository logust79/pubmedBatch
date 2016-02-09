use Module::Build;
my $build = Module::Build->new
(
	 module_name => 'pubmedBatch',
	 license => 'perl',
	 requires => {
		          'perl'		=> '5.14.0',
		         },
);

$build->create_build_script;
