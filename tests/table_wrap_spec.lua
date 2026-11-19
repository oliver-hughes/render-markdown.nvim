---@module 'luassert'

local util = require('tests.util')

describe('table wrapping', function()
    local lines = {
        'BEFORE',
        '',
        '| Name | Description |',
        '| --- | --- |',
        '| **bold** | Here is a long description with [a link](https://example.com) and `some code` and 行行行. |',
        '| short | Another very long description which should wrap into several lines neatly. |',
        '',
        'AFTER',
    }
    local rendered = {
        'BEFORE',
        '┌───────┬──────────────────────────────┐',
        '│ Name  │ Description                  │',
        '├───────┼──────────────────────────────┤',
        '│ bold  │ Here is a long description   │',
        '│       │ with 󰖟 a link and some code  │',
        '│       │ and 行行行.                  │',
        '│ short │ Another very long            │',
        '│       │ description which should     │',
        '│       │ wrap into several lines      │',
        '│       │ neatly.                      │',
        '└───────┴──────────────────────────────┘',
        'AFTER',
    }
    local mixed = {
        'BEFORE',
        '',
        '| A | B | C |',
        '| :- | :-: | -: |',
        '| x | y | short |',
        '| z | w | one two three four five six seven eight nine ten |',
        '| a | b | end |',
        '',
        'AFTER',
    }
    local mixed_rendered = {
        'BEFORE',
        '┌───┬───┬──────────────────────────────┐',
        '│ A │ B │                            C │',
        '├━──┼━─━┼─────────────────────────────━┤',
        '│ x │ y │                        short │',
        '│ z │ w │  one two three four five six │',
        '│   │   │         seven eight nine ten │',
        '│ a │ b │                          end │',
        '└───┴───┴──────────────────────────────┘',
        'AFTER',
    }

    before_each(function()
        vim.o.columns = 40
        vim.o.wrap = true
        vim.o.number = false
        vim.o.signcolumn = 'no'
    end)

    it('trimmed', function()
        util.setup.text(lines, { pipe_table = { cell = 'trimmed' } })
        util.assert_screen(rendered)
    end)

    it('padded', function()
        util.setup.text(lines, { pipe_table = { cell = 'padded' } })
        util.assert_screen(rendered)
    end)

    it('nowrap', function()
        vim.o.wrap = false
        util.setup.text(lines, { pipe_table = { cell = 'trimmed' } })
        util.assert_screen(rendered)
    end)

    it('fitting table', function()
        util.setup.text({
            '',
            '| A | B |',
            '| - | - |',
            '| x | y |',
            '',
        }, { pipe_table = { cell = 'trimmed' } })
        util.assert_screen({
            '┌───┬───┐',
            '│ A │ B │',
            '├───┼───┤',
            '│ x │ y │',
            '└───┴───┘',
        })
    end)

    it('concealed destination wider than the window', function()
        util.setup.text({
            '',
            '| A | B |',
            '| - | - |',
            '| x | [link](https://example.com/a/long/destination/that/exceeds/the/window) |',
            'AFTER',
        }, { pipe_table = { cell = 'trimmed' } })
        util.assert_screen({
            '┌───┬────────┐',
            '│ A │ B      │',
            '├───┼────────┤',
            '│ x │ 󰖟 link │',
            '└───┴────────┘',
            'AFTER',
        })
    end)

    it('delimiter wider than the window', function()
        util.setup.text({
            'BEFORE',
            '',
            '| A | B |',
            '| - | ------------------------------------------------------------ |',
            '| x | y |',
            '',
            'AFTER',
        }, { pipe_table = { cell = 'trimmed' } })
        util.assert_screen({
            'BEFORE',
            '┌───┬───┐',
            '│ A │ B │',
            '├───┼───┤',
            '│ x │ y │',
            '└───┴───┘',
            'AFTER',
        })
    end)

    it('mixed rows and alignments', function()
        util.setup.text(mixed, { pipe_table = { cell = 'trimmed' } })
        util.assert_screen(mixed_rendered)
    end)

    it('mixed rows with nowrap', function()
        vim.o.wrap = false
        util.setup.text(mixed, { pipe_table = { cell = 'trimmed' } })
        util.assert_screen(mixed_rendered)
    end)

    it('cursor on a fitting row', function()
        util.setup.text(mixed, { pipe_table = { cell = 'trimmed' } })
        util.set_row(5)
        util.assert_screen(mixed_rendered)
    end)

    it('source padding with nowrap', function()
        vim.o.wrap = false
        util.setup.text({
            'BEFORE',
            '',
            '| A | B |',
            '| - | - |',
            '| x | padded                                                                     |',
            '| y | one two three four five six seven eight nine ten |',
            '',
            'AFTER',
        }, { pipe_table = { cell = 'padded' } })
        util.set_row(5)
        util.assert_screen({
            'BEFORE',
            '┌───┬──────────────────────────────────┐',
            '│ A │ B                                │',
            '├───┼──────────────────────────────────┤',
            '│ x │ padded                           │',
            '│ y │ one two three four five six      │',
            '│   │ seven eight nine ten             │',
            '└───┴──────────────────────────────────┘',
            'AFTER',
        })
    end)

    it('inline code decorations at the cell end', function()
        util.setup.text({
            'BEFORE',
            '',
            '| A | B |',
            '| - | - |',
            '| x | one two three four five six seven eight `code` |',
            '',
            'AFTER',
        }, {
            pipe_table = { cell = 'trimmed' },
            code = { inline_left = '(', inline_right = ')' },
        })
        util.assert_screen({
            'BEFORE',
            '┌───┬──────────────────────────────────┐',
            '│ A │ B                                │',
            '├───┼──────────────────────────────────┤',
            '│ x │ one two three four five six      │',
            '│   │ seven eight (code)               │',
            '└───┴──────────────────────────────────┘',
            'AFTER',
        })
    end)

    it('grid', function()
        util.setup.text(mixed, {
            pipe_table = { cell = 'trimmed', grid = true },
        })
        util.assert_screen({
            'BEFORE',
            '┌───┬───┬──────────────────────────────┐',
            '│ A │ B │                            C │',
            '├━──┼━─━┼─────────────────────────────━┤',
            '│ x │ y │                        short │',
            '├───┼───┼──────────────────────────────┤',
            '│ z │ w │  one two three four five six │',
            '│   │   │         seven eight nine ten │',
            '├───┼───┼──────────────────────────────┤',
            '│ a │ b │                          end │',
            '└───┴───┴──────────────────────────────┘',
            'AFTER',
        })
    end)

    it('virtual borders', function()
        util.setup.text(mixed, {
            pipe_table = { cell = 'trimmed', border_virtual = true },
        })
        util.assert_screen({
            'BEFORE',
            '',
            '┌───┬───┬──────────────────────────────┐',
            '│ A │ B │                            C │',
            '├━──┼━─━┼─────────────────────────────━┤',
            '│ x │ y │                        short │',
            '│ z │ w │  one two three four five six │',
            '│   │   │         seven eight nine ten │',
            '│ a │ b │                          end │',
            '└───┴───┴──────────────────────────────┘',
            '',
            'AFTER',
        })
    end)

    it('quote', function()
        util.setup.text({
            'BEFORE',
            '',
            '> | A | B |',
            '> | - | - |',
            '> | x | one two three four five six seven eight nine ten |',
            '',
            'AFTER',
        }, { pipe_table = { cell = 'trimmed' } })
        util.assert_screen({
            'BEFORE',
            '  ┌───┬────────────────────────────────┐',
            '▋ │ A │ B                              │',
            '▋ ├───┼────────────────────────────────┤',
            '▋ │ x │ one two three four five six    │',
            '▋ │   │ seven eight nine ten           │',
            '  └───┴────────────────────────────────┘',
            'AFTER',
        })
    end)

    it('quote grid', function()
        util.setup.text({
            'BEFORE',
            '',
            '> | A | B |',
            '> | - | - |',
            '> | 1 | 2 |',
            '> | 3 | 4 |',
            '> | 5 | 6 |',
            '',
            'AFTER',
        }, { pipe_table = { cell = 'trimmed', grid = true } })
        util.assert_screen({
            'BEFORE',
            '  ┌───┬───┐',
            '▋ │ A │ B │',
            '▋ ├───┼───┤',
            '▋ │ 1 │ 2 │',
            '▋ ├───┼───┤',
            '▋ │ 3 │ 4 │',
            '▋ ├───┼───┤',
            '▋ │ 5 │ 6 │',
            '  └───┴───┘',
            'AFTER',
        })
    end)

    it('section indentation', function()
        util.setup.text({
            '# Section',
            '',
            '| A | B |',
            '| - | - |',
            '| x | one two three four five six seven eight nine ten |',
        }, {
            pipe_table = { cell = 'padded' },
            heading = { enabled = false },
            indent = { enabled = true, skip_level = 0, per_level = 2 },
        })
        util.assert_screen({
            '▎ # Section',
            '▎',
            '▎ ┌───┬────────────────────────────────┐',
            '▎ │ A │ B                              │',
            '▎ ├───┼────────────────────────────────┤',
            '▎ │ x │ one two three four five six    │',
            '▎ │   │ seven eight nine ten           │',
            '▎ └───┴────────────────────────────────┘',
        })
    end)

    it('viewport-dependent widths', function()
        local input = { '', '| A | B |', '| - | - |' }
        for _ = 1, 100 do
            input[#input + 1] = '| x | y |'
        end
        input[#input + 1] = '| x | ' .. ('long '):rep(40) .. '|'
        util.setup.text(input, {
            debounce = 0,
            pipe_table = { cell = 'trimmed' },
        })
        local expected = {
            '┌───┬───┐',
            '│ A │ B │',
            '├───┼───┤',
        }
        for _ = 1, 36 do
            expected[#expected + 1] = '│ x │ y │'
        end
        expected[#expected + 1] = ''
        util.assert_screen(expected)

        util.set_row(100, true)
        util.assert_screen({
            '│ x │ y                                │',
            '│ x │ y                                │',
            '│ x │ y                                │',
            '│ x │ y                                │',
            '│ x │ long long long long long long    │',
            '│   │ long long long long long long    │',
            '│   │ long long long long long long    │',
            '│   │ long long long long long long    │',
            '│   │ long long long long long long    │',
            '│   │ long long long long long long    │',
            '│   │ long long long long              │',
            '└───┴──────────────────────────────────┘',
        })
    end)

    it('EOF', function()
        util.setup.text({
            '',
            '| A | B | C |',
            '| :- | :-: | -: |',
            '| x | y | short |',
            '| z | w | one two three four five six seven eight nine ten |',
        }, { pipe_table = { cell = 'trimmed' } })
        util.assert_screen({
            '┌───┬───┬──────────────────────────────┐',
            '│ A │ B │                            C │',
            '├━──┼━─━┼─────────────────────────────━┤',
            '│ x │ y │                        short │',
            '│ z │ w │  one two three four five six │',
            '│   │   │         seven eight nine ten │',
            '└───┴───┴──────────────────────────────┘',
        })
    end)

    it('cursor on header at BOF', function()
        util.setup.text({
            '| Name | Description |',
            '| --- | --- |',
            '| **bold** | Here is a long description with [a link](https://example.com) and `some code` and 行行行. |',
            '| short | Another very long description which should wrap into several lines neatly. |',
        }, {
            anti_conceal = { enabled = true },
            pipe_table = { cell = 'trimmed' },
        })
        util.assert_screen({
            '| Name | Description |',
            '├───────┼──────────────────────────────┤',
            '│ bold  │ Here is a long description   │',
            '│       │ with 󰖟 a link and some code  │',
            '│       │ and 行行行.                  │',
            '│ short │ Another very long            │',
            '│       │ description which should     │',
            '│       │ wrap into several lines      │',
            '│       │ neatly.                      │',
            '└───────┴──────────────────────────────┘',
        })
    end)

    it('cursor on wrapped row', function()
        util.setup.text(mixed, { pipe_table = { cell = 'trimmed' } })
        util.assert_screen(mixed_rendered)

        util.set_row(6)
        util.assert_screen({
            'BEFORE',
            '┌───┬───┬──────────────────────────────┐',
            '│ A │ B │                            C │',
            '├━──┼━─━┼─────────────────────────────━┤',
            '│ x │ y │                        short │',
            '| z | w | one two three four five six se',
            'ven eight nine ten |',
            '│ a │ b │                          end │',
            '└───┴───┴──────────────────────────────┘',
            'AFTER',
        })

        util.set_row(1)
        util.assert_screen(mixed_rendered)
    end)

    it('cursor on wrapped row with nowrap', function()
        vim.o.wrap = false
        util.setup.text(mixed, { pipe_table = { cell = 'trimmed' } })
        util.set_row(6)
        util.assert_screen({
            'BEFORE',
            '┌───┬───┬──────────────────────────────┐',
            '│ A │ B │                            C │',
            '├━──┼━─━┼─────────────────────────────━┤',
            '│ x │ y │                        short │',
            '| z | w | one two three four five six se',
            '│ a │ b │                          end │',
            '└───┴───┴──────────────────────────────┘',
            'AFTER',
        })
    end)

    it('heading after table', function()
        util.setup.text({
            'BEFORE',
            '',
            '| A | B | C |',
            '| :- | :-: | -: |',
            '| x | y | short |',
            '| z | w | one two three four five six seven eight nine ten |',
            '# Heading',
        }, {
            pipe_table = { cell = 'trimmed' },
            heading = { border = true },
        })
        util.assert_screen({
            'BEFORE',
            '┌───┬───┬──────────────────────────────┐',
            '│ A │ B │                            C │',
            '├━──┼━─━┼─────────────────────────────━┤',
            '│ x │ y │                        short │',
            '│ z │ w │  one two three four five six │',
            '│   │   │         seven eight nine ten │',
            '└───┴───┴──────────────────────────────┘',
            '▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄',
            '󰲡 Heading',
            '▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀',
        })
    end)

    it('minimum widths cannot fit', function()
        vim.o.wrap = false
        util.setup.text({
            'BEFORE',
            '',
            '| A | B |',
            '| - | - |',
            '| x | y |',
            '',
            'AFTER',
        }, { pipe_table = { cell = 'trimmed', min_width = 20 } })
        util.assert_screen({
            'BEFORE',
            '┌────────────────────┬──────────────────',
            '│ A                  │ B',
            '├────────────────────┼──────────────────',
            '│ x                  │ y',
            '└────────────────────┴──────────────────',
            'AFTER',
        })
    end)

    it('raw cells', function()
        vim.o.wrap = false
        util.setup.text(mixed, { pipe_table = { cell = 'raw' } })
        util.assert_screen({
            'BEFORE',
            '',
            '│ A │ B │ C │',
            '├━───┼━───━┼────────────────────────────',
            '│ x │ y │ short │',
            '│ z │ w │ one two three four five six se',
            '│ a │ b │ end │',
            '',
            'AFTER',
        })
    end)

    it('conceallevel 1', function()
        vim.o.wrap = false
        util.setup.text(mixed, {
            pipe_table = { cell = 'trimmed' },
            win_options = { conceallevel = { rendered = 1 } },
        })
        util.assert_screen({
            'BEFORE',
            '┌───┬───┬───────────────────────────────',
            '│ A │ B │',
            '├━──┼━─━┼───────────────────────────────',
            '│ x │ y │',
            '│ z │ w │ one two three four five six se',
            '│ a │ b │',
            '└───┴───┴───────────────────────────────',
            'AFTER',
        })
    end)

    describe('overlay', function()
        ---@type render.md.table.UserConfig
        local overlay = { cell = 'trimmed', wrap_mode = 'overlay' }
        local tall = {
            'BEFORE',
            '',
            '| A | B |',
            '| - | - |',
            '| one two three four five six seven eight | nine ten eleven twelve thirteen |',
            '| x | y |',
            '',
            'AFTER',
        }
        local tall_rendered = {
            'BEFORE',
            '┌───────────────────┬──────────────────┐',
            '│ A                 │ B                │',
            '├───────────────────┼──────────────────┤',
            '│ one two three     │ nine ten eleven  │',
            '│ four five six     │ twelve thirteen  │',
            '│ seven eight       │                  │',
            '│ x                 │ y                │',
            '└───────────────────┴──────────────────┘',
            'AFTER',
        }

        it('cursor on wrapped row', function()
            util.setup.text(mixed, {
                anti_conceal = { enabled = true },
                pipe_table = overlay,
            })
            util.assert_screen(mixed_rendered)

            util.set_row(6)
            util.assert_screen({
                'BEFORE',
                '┌───┬───┬──────────────────────────────┐',
                '│ A │ B │                            C │',
                '├━──┼━─━┼─────────────────────────────━┤',
                '│ x │ y │                        short │',
                '| z | w | one two three four five six se',
                'ven eight nine ten |',
                '│ a │ b │                          end │',
                '└───┴───┴──────────────────────────────┘',
                'AFTER',
            })

            util.set_row(5)
            util.assert_screen({
                'BEFORE',
                '┌───┬───┬──────────────────────────────┐',
                '│ A │ B │                            C │',
                '├━──┼━─━┼─────────────────────────────━┤',
                '| x | y | short |',
                '│ z │ w │  one two three four five six │',
                '│   │   │         seven eight nine ten │',
                '│ a │ b │                          end │',
                '└───┴───┴──────────────────────────────┘',
                'AFTER',
            })
        end)

        it('row taller than its text', function()
            util.setup.text(tall, {
                anti_conceal = { enabled = true },
                pipe_table = overlay,
            })
            util.assert_screen(tall_rendered)

            -- an empty line holds the rest of the row so nothing below moves
            util.set_row(5)
            util.assert_screen({
                'BEFORE',
                '┌───────────────────┬──────────────────┐',
                '│ A                 │ B                │',
                '├───────────────────┼──────────────────┤',
                '| one two three four five six seven eigh',
                't | nine ten eleven twelve thirteen |',
                '',
                '│ x                 │ y                │',
                '└───────────────────┴──────────────────┘',
                'AFTER',
            })
        end)

        it('text taller than its row', function()
            util.setup.text({
                'BEFORE',
                '',
                '| A | B |',
                '| - | - |',
                '| x | [link](https://example.com/a/long/destination/that/exceeds/the/window) |',
                '| y | one two three four five six seven eight nine ten |',
                '',
                'AFTER',
            }, {
                anti_conceal = { enabled = true },
                pipe_table = overlay,
            })
            util.assert_screen({
                'BEFORE',
                '┌───┬──────────────────────────────────┐',
                '│ A │ B                                │',
                '├───┼──────────────────────────────────┤',
                '│ x │ 󰖟 link                           │',
                '│   │                                  │',
                '│ y │ one two three four five six      │',
                '│   │ seven eight nine ten             │',
                '└───┴──────────────────────────────────┘',
                'AFTER',
            })

            util.set_row(5)
            util.assert_screen({
                'BEFORE',
                '┌───┬──────────────────────────────────┐',
                '│ A │ B                                │',
                '├───┼──────────────────────────────────┤',
                '| x | link',
                ' |',
                '│ y │ one two three four five six      │',
                '│   │ seven eight nine ten             │',
                '└───┴──────────────────────────────────┘',
                'AFTER',
            })
        end)

        it('nowrap', function()
            vim.o.wrap = false
            util.setup.text(tall, {
                anti_conceal = { enabled = true },
                pipe_table = overlay,
            })
            util.assert_screen(tall_rendered)

            util.set_row(5)
            util.assert_screen({
                'BEFORE',
                '┌───────────────────┬──────────────────┐',
                '│ A                 │ B                │',
                '├───────────────────┼──────────────────┤',
                '| one two three four five six seven eigh',
                '',
                '',
                '│ x                 │ y                │',
                '└───────────────────┴──────────────────┘',
                'AFTER',
            })
        end)

        it('grid', function()
            util.setup.text(mixed, {
                pipe_table = vim.tbl_extend('force', overlay, { grid = true }),
            })
            util.assert_screen({
                'BEFORE',
                '┌───┬───┬──────────────────────────────┐',
                '│ A │ B │                            C │',
                '├━──┼━─━┼─────────────────────────────━┤',
                '│ x │ y │                        short │',
                '├───┼───┼──────────────────────────────┤',
                '│ z │ w │  one two three four five six │',
                '│   │   │         seven eight nine ten │',
                '├───┼───┼──────────────────────────────┤',
                '│ a │ b │                          end │',
                '└───┴───┴──────────────────────────────┘',
                'AFTER',
            })
        end)

        it('delimiter wider than the window', function()
            util.setup.text({
                'BEFORE',
                '',
                '| A | B |',
                '| - | ------------------------------------------------------------ |',
                '| x | y |',
                '',
                'AFTER',
            }, {
                anti_conceal = { enabled = true },
                pipe_table = overlay,
            })
            util.assert_screen({
                'BEFORE',
                '┌───┬───┐',
                '│ A │ B │',
                '├───┼───┤',
                '│   │   │',
                '│ x │ y │',
                '└───┴───┘',
                'AFTER',
            })

            util.set_row(4)
            util.assert_screen({
                'BEFORE',
                '┌───┬───┐',
                '│ A │ B │',
                '| - | ----------------------------------',
                '-------------------------- |',
                '│ x │ y │',
                '└───┴───┘',
                'AFTER',
            })
        end)

        it('anti-conceal ignored', function()
            util.setup.text(mixed, {
                anti_conceal = {
                    enabled = true,
                    ignore = { table_border = { 'n' } },
                },
                pipe_table = overlay,
            })
            util.set_row(6)
            util.assert_screen(mixed_rendered)
        end)

        it('whole table measured', function()
            local input = { '', '| A | B |', '| - | - |' }
            for _ = 1, 100 do
                input[#input + 1] = '| x | y |'
            end
            input[#input + 1] = '| x | ' .. ('long '):rep(40) .. '|'
            util.setup.text(input, { debounce = 0, pipe_table = overlay })
            local expected = {
                '┌───┬──────────────────────────────────┐',
                '│ A │ B                                │',
                '├───┼──────────────────────────────────┤',
            }
            for _ = 1, 36 do
                expected[#expected + 1] =
                    '│ x │ y                                │'
            end
            expected[#expected + 1] = ''
            util.assert_screen(expected)
        end)

        it('cursor line', function()
            vim.o.cursorline = true
            util.setup.text(mixed, { pipe_table = overlay })
            util.set_row(6)
            util.assert_screen(mixed_rendered)

            -- whether each overlay shown on a row has the cursor line highlight
            -- in any namespace, as overlays can be scoped to their window
            local ns = -1
            ---@param row integer
            ---@return boolean[]
            local function lit(row)
                local marks = vim.api.nvim_buf_get_extmarks(
                    0,
                    ns,
                    { row, 0 },
                    { row, -1 },
                    { details = true }
                )
                local result = {} ---@type boolean[]
                for _, mark in ipairs(marks) do
                    local virt_text = mark[4].virt_text
                    if virt_text then
                        local hl = virt_text[1][2]
                        result[#result + 1] = type(hl) == 'table'
                            and vim.tbl_contains(hl, 'CursorLine')
                    end
                end
                return result
            end
            -- rows 4 and 6 take up one screen line, row 5 takes up two
            assert.same({ false }, lit(4))
            assert.same({ true, true }, lit(5))
            assert.same({ false }, lit(6))

            util.set_row(5)
            assert.same({ true }, lit(4))
            assert.same({ false, false }, lit(5))
            assert.same({ false }, lit(6))
            vim.o.cursorline = false
        end)

        describe('windows', function()
            ---@type render.md.UserConfig
            local opts = { debounce = 0, pipe_table = overlay }

            ---@param win integer
            ---@return string[]
            local function screen(win)
                vim.cmd('redraw')
                local pos = vim.api.nvim_win_get_position(win)
                local width = vim.api.nvim_win_get_width(win)
                local height = vim.api.nvim_win_get_height(win)
                local result = {} ---@type string[]
                for row = pos[1] + 1, pos[1] + height do
                    local line = ''
                    for col = pos[2] + 1, pos[2] + width do
                        line = line .. vim.fn.screenstring(row, col)
                    end
                    line = line:gsub('%s+$', '')
                    if line == '~' then
                        break
                    end
                    result[#result + 1] = line
                end
                return result
            end

            ---Draws the buffer again in every window on it, as a resize does.
            ---@param buf integer
            local function resized(buf)
                require('render-markdown').render({
                    buf = buf,
                    event = 'WinResized',
                })
                vim.wait(0)
            end

            ---Opens a second window on the current buffer, the current window
            ---ends up 50 wide and the new one, which becomes current, 30.
            ---@param resize? boolean
            ---@return integer wide, integer narrow, integer buf
            local function split(resize)
                local buf = vim.api.nvim_get_current_buf()
                local wide = vim.api.nvim_get_current_win()
                vim.cmd('vsplit')
                local narrow = vim.api.nvim_get_current_win()
                vim.api.nvim_win_set_width(narrow, 30)
                if resize ~= false then
                    resized(buf)
                end
                return wide, narrow, buf
            end

            ---How a window draws the buffer while it is the only one on it.
            ---@param win integer
            ---@param other integer
            ---@param buf integer
            ---@return string[]
            local function alone(win, other, buf)
                local empty = vim.api.nvim_create_buf(false, true)
                vim.api.nvim_win_set_buf(other, empty)
                resized(buf)
                local result = screen(win)
                vim.api.nvim_win_set_buf(other, buf)
                resized(buf)
                return result
            end

            before_each(function()
                vim.o.columns = 81
            end)

            after_each(function()
                vim.cmd('only')
            end)

            it('each window wraps rows for its own width', function()
                util.setup.text(mixed, opts)
                local wide, narrow, buf = split()
                local actual_wide, actual_narrow = screen(wide), screen(narrow)
                assert.same({
                    'BEFORE',
                    '┌───┬───┬────────────────────┐',
                    '│ A │ B │                  C │',
                    '├━──┼━─━┼───────────────────━┤',
                    '│ x │ y │              short │',
                    '│ z │ w │ one two three four │',
                    '│   │   │     five six seven │',
                    '│   │   │     eight nine ten │',
                    '│ a │ b │                end │',
                    '└───┴───┴────────────────────┘',
                    'AFTER',
                }, actual_narrow)
                assert.same(alone(wide, narrow, buf), actual_wide)
                assert.same(alone(narrow, wide, buf), actual_narrow)
            end)

            it('a new window is drawn without being resized', function()
                util.setup.text(mixed, opts)
                local wide, narrow, buf = split(false)
                -- moving the cursor finds the buffer in a new window
                vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
                vim.wait(0)
                local actual_wide, actual_narrow = screen(wide), screen(narrow)
                assert.same(alone(wide, narrow, buf), actual_wide)
                assert.same(alone(narrow, wide, buf), actual_narrow)
            end)

            it('the cursor only reveals its row in its own window', function()
                util.setup.text(
                    mixed,
                    vim.tbl_extend('force', opts, {
                        anti_conceal = { enabled = true },
                    })
                )
                local wide, narrow, buf = split()
                local expected_wide = alone(wide, narrow, buf)

                -- the narrow window is current
                util.set_row(6)
                assert.same({
                    'BEFORE',
                    '┌───┬───┬────────────────────┐',
                    '│ A │ B │                  C │',
                    '├━──┼━─━┼───────────────────━┤',
                    '│ x │ y │              short │',
                    '| z | w | one two three four f',
                    'ive six seven eight nine ten |',
                    '',
                    '│ a │ b │                end │',
                    '└───┴───┴────────────────────┘',
                    'AFTER',
                }, screen(narrow))
                assert.same(expected_wide, screen(wide))
            end)

            it('virtual text stays where a row is not drawn over', function()
                -- fits the wide window, the narrow one draws over its rows
                util.setup.text({
                    'BEFORE',
                    '',
                    '| A | B |',
                    '| - | - |',
                    '| x | see [docs](https://e.io) now |',
                    '',
                    'AFTER',
                }, opts)
                local wide, narrow, buf = split()
                local actual_wide, actual_narrow = screen(wide), screen(narrow)
                assert.same({
                    'BEFORE',
                    '┌───┬────────────────┐',
                    '│ A │ B              │',
                    '├───┼────────────────┤',
                    '│ x │ see 󰖟 docs now │',
                    '└───┴────────────────┘',
                    'AFTER',
                }, actual_wide)
                assert.same(alone(wide, narrow, buf), actual_wide)
                assert.same(alone(narrow, wide, buf), actual_narrow)
            end)

            it('a closed window frees its namespace', function()
                util.setup.text(mixed, opts)
                local scope = require('render-markdown.lib.scope')
                local wide, narrow, buf = split()
                local ns = assert(scope.find(narrow))
                ---@return integer
                local function count()
                    return #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
                end
                assert.is_true(count() > 0)

                vim.api.nvim_win_close(narrow, true)
                resized(buf)
                assert.is_nil(scope.find(narrow))
                assert.same(0, count())

                -- the next window takes it over and is drawn for its own width
                local _, other = split()
                assert.same(ns, scope.find(other))
                assert.same(alone(other, wide, buf), screen(other))
            end)
        end)
    end)
end)
