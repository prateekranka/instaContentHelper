# Mira keyboard actions

## Failure modes before implementation

| Failure mode | Behavior to verify |
| --- | --- |
| The software keyboard covers the main button or leaves it in the scroll area. | Type in the field and tap the main button with the keyboard open. On Home and in long forms, scroll the form without moving the button. |
| The footer overlaps the last field, the tab bar, or the Ask Mira bar. | Scroll to the last field in a long form. Check that the footer stays above the keyboard and that the field and button can both receive taps. |
| Moving the button changes which action runs or bypasses validation. | Check that an empty field leaves its action disabled when required. Enter text and check that one tap runs the existing action once. |
| The Done key sends the request or adds an unwanted newline. | Check that Done closes the keyboard and leaves the text available. Check that multiline paste still keeps its line breaks. |
| An outside tap either leaves the keyboard open or blocks the control under the tap. | Tap page space and a secondary control. Check that the keyboard closes. Check that another text field still takes focus when tapped. |
| A larger text size leaves too little room to edit or clips the main button. | Check the footer and scrolling at a large text size. |
| Moving the button changes its accessibility name or ID, or exposes two copies. | Check that the existing locator resolves to one button and that the button responds to a tap. |
| A sheet or a tab inherits focus from another screen. | Open a sheet from a field, close the sheet, and switch tabs. Check that each input and its Done key respond on the correct screen. |

## PR #47 screen inventory

| Screen | Main action for text entry |
| --- | --- |
| Home request | Make |
| Ask Mira sheet, including ideas, words, shots and filming plan | Get ideas or Propose change |
| Your words, Change it | Send |
| Your Reel, idea request and filming details | Show three ideas or More ideas |
| Your Reel, script fields and project name | Make shot list, Update shot list, or Draft hook, script and caption |
| Your Reel, project name on the Shots tab | Start filming, Approve your words, or Update shot list |
| My Brand, Rename project | Save name |
| Profile | Done |
| Your own idea | Use my idea |
| Brand requirements | Get requirements or Confirm requirements, according to the brief state |
| Deals, Brand brief sheet | Save as a Reel brief |
| Ask Mira bar on Home, My Brand, Deals, Your Reel, Today’s ideas, Your words, the filming screen and the Done screen | Send to Mira |

The speech transcript field uses the same form and the existing Use these words control. Profile and the project name in the Reel editor keep their existing save behavior.
