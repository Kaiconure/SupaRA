# SupaRA

A new and improved automated ranged attack addon. You might even call it a *super* ranged attack addon.

Get the latest and greatest SupaRA addon from out [GitHub page](https://github.com/Kaiconure/SupaRA).

### Feature highlights

- **Automatically determines the optimal firing interval**. Windower events are tracked directly, so it knows when you're ready to fire another shot.
- **Ensures that you're always facing toward your target** to avoid "You cannot see *target*" errors.
- **Detects when appropriate ranged attack gear is equipped**, and automatically stops if you run out of ammo.
- **Detects status changes**, such as death, healing, or mounting, and automatically stops firing.
- **SupaRA will *not* work with consumable thrown items.** This is to save you from losing that expensive rare/ex sachet due to automation. Nothing can stop you from accidentally throwing it yourself,unfortunately. 
  - *Disclaimer: I make no guarantees that this protection will work in 100% of scenarios. It's in your best interest to take the appropriate precautions, and I will not be held responsible for mistakes.*

### Usage

Commands may be passed to SupaRA in the standard way:

```//supara <command> <arguments>```

SupaRA has a shorthand alias of `sra`, so you could instead run:

```//sra <command> <arguments>```



### Commands

The following commands are supported by SupaRA.

**help**

Displays the in-game usage notes for SupaRA. Run as `//sra help`.

**start** 

Starts the automatic ranged attack sequence on the targeted mob.  Run as `//sra start`.

**stop**

Stops the automatic ranged attack sequence. Run as `//sra stop`.

**toggle**

Toggles the automatic ranged attack sequence. Run as `//sra toggle`, or simply by hitting **Ctrl+D** on the keyboard.