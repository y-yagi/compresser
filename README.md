# Compresser

Compresser packs a Ruby gem and the files it `require`s into a single, self-contained `.rb` file.

It starts from a gem's entry point, follows every `require` / `require_relative` (across the gem's own files, its dependencies, and the Ruby standard library), and concatenates them into one file with the now-redundant `require` lines and duplicated magic comments removed. The result is a single file you can drop in without managing load paths.

## Installation

```ruby
gem "compresser"
```

## Usage

Run the `compresser` executable with a gem name. By default the packed file is printed to standard output:

```bash
compresser GEM_NAME
```

Write the result to a file with `-o` / `--output`:

```bash
compresser uri -o uri.rb
```

The target gem must be installed and resolvable in the current environment (for example, run it through `bundle exec` when using a `Gemfile`):

```bash
bundle exec compresser uri -o uri.rb
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/y-yagi/compresser. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/y-yagi/compresser/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Compresser project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/y-yagi/compresser/blob/main/CODE_OF_CONDUCT.md).
