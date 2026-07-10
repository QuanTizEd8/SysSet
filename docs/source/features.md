# Features

This section provides a reference for all available features, with detailed documentation on their options, behavior, and installation instructions. For general guidance on installing and using features, see the [User Guide](user-guide.md).

::::{grid} 1
:gutter: 3

|{% for feat_id, feat in feats|dictsort %}|
:::{grid-item-card} |{{ feat.name }}| – `|{{ feat_id }}|`
:class-title: sd-text-center
:link: /features/|{{ feat_id }}|/index
:link-type: doc

<div style="text-align:center">

|{% for keyword in feat.keywords -%}|
{bdg-info}`|{{ keyword }}|`
|{% endfor %}|

</div>

|{{ feat.description }}|
:::
|{% endfor %}|

::::
