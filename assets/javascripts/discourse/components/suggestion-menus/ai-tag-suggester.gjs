import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DropdownMenu from "discourse/components/dropdown-menu";
import discourseTag from "discourse/helpers/discourse-tag";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import i18n from "discourse-common/helpers/i18n";
import DMenu from "float-kit/components/d-menu";
import { MIN_CHARACTER_COUNT } from "../../lib/ai-helper-suggestions";

export default class AiTagSuggester extends Component {
  @service siteSettings;
  @service toasts;
  @tracked loading = false;
  @tracked suggestions = null;
  @tracked untriggers = [];
  @tracked triggerIcon = "discourse-sparkles";
  @tracked content = null;
  @tracked topicContent = null;

  constructor() {
    super(...arguments);
    if (!this.topicContent && this.args.composer?.reply === undefined) {
      this.fetchTopicContent();
    }
  }

  async fetchTopicContent() {
    await ajax(`/t/${this.args.buffered.content.id}.json`).then(
      ({ post_stream }) => {
        this.topicContent = post_stream.posts[0].cooked;
      }
    );
  }

  get showSuggestionButton() {
    const composerFields = document.querySelector(".composer-fields");
    this.content = this.args.composer?.reply || this.topicContent;
    const showTrigger = this.content?.length > MIN_CHARACTER_COUNT;

    if (composerFields) {
      if (showTrigger) {
        composerFields.classList.add("showing-ai-suggestions");
      } else {
        composerFields.classList.remove("showing-ai-suggestions");
      }
    }

    return this.siteSettings.ai_embeddings_enabled && showTrigger;
  }

  get showDropdown() {
    if (this.suggestions?.length <= 0) {
      this.dMenu.close();
    }
    return !this.loading && this.suggestions?.length > 0;
  }

  @action
  async loadSuggestions() {
    if (
      this.suggestions &&
      this.suggestions?.length > 0 &&
      !this.dMenu.expanded
    ) {
      return this.suggestions;
    }

    this.loading = true;
    this.triggerIcon = "spinner";

    try {
      const { assistant } = await ajax("/discourse-ai/ai-helper/suggest_tags", {
        method: "POST",
        data: { text: this.content },
      });
      this.suggestions = assistant;
      const model = this.args.composer
        ? this.args.composer
        : this.args.buffered;
      if (this.#tagSelectorHasValues()) {
        this.suggestions = this.suggestions.filter(
          (s) => !model.get("tags").includes(s.name)
        );
      }

      if (this.suggestions?.length <= 0) {
        this.toasts.error({
          class: "ai-suggestion-error",
          duration: 3000,
          data: {
            message: i18n(
              "discourse_ai.ai_helper.suggest_errors.no_suggestions"
            ),
          },
        });
        return;
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
      this.triggerIcon = "sync-alt";
    }

    return this.suggestions;
  }

  #tagSelectorHasValues() {
    return this.args.composer?.tags && this.args.composer?.tags.length > 0;
  }

  #removedAppliedTag(suggestion) {
    return (this.suggestions = this.suggestions.filter(
      (s) => s.id !== suggestion.id
    ));
  }

  @action
  applySuggestion(suggestion) {
    const maxTags = this.siteSettings.max_tags_per_topic;
    const model = this.args.composer ? this.args.composer : this.args.buffered;
    if (!model) {
      return;
    }

    const tags = model.get("tags");

    if (!tags) {
      model.set("tags", [suggestion.name]);
      this.#removedAppliedTag(suggestion);
      return;
    }

    if (tags?.length >= maxTags) {
      return this.toasts.error({
        class: "ai-suggestion-error",
        duration: 3000,
        data: {
          message: i18n("discourse_ai.ai_helper.suggest_errors.too_many_tags", {
            count: maxTags,
          }),
        },
      });
    }

    tags.push(suggestion.name);
    model.set("tags", [...tags]);
    suggestion.disabled = true;
    this.#removedAppliedTag(suggestion);
  }

  @action
  onRegisterApi(api) {
    this.dMenu = api;
  }

  @action
  onClose() {
    if (this.suggestions?.length > 0) {
      // If all suggestions have been used,
      // re-triggering when no suggestions present
      // will cause computation issues with
      // setting the icon, so we prevent it
      this.triggerIcon = "discourse-sparkles";
    }
  }

  <template>
    {{#if this.showSuggestionButton}}
      <DMenu
        @title={{i18n "discourse_ai.ai_helper.suggest"}}
        @icon={{this.triggerIcon}}
        @identifier="ai-tag-suggester"
        @onClose={{this.onClose}}
        @triggerClass="suggestion-button suggest-tags-button {{if
          this.loading
          'is-loading'
        }}"
        @contentClass="ai-suggestions-menu"
        @onRegisterApi={{this.onRegisterApi}}
        @modalForMobile={{true}}
        @untriggers={{this.untriggers}}
        {{on "click" this.loadSuggestions}}
      >
        <:content>
          {{#if this.showDropdown}}
            <DropdownMenu as |dropdown|>
              {{#each this.suggestions as |suggestion index|}}
                <dropdown.item>
                  <DButton
                    class="tag-row"
                    data-name={{suggestion.name}}
                    data-value={{index}}
                    title={{suggestion.name}}
                    @disabled={{this.isDisabled suggestion}}
                    @action={{fn this.applySuggestion suggestion}}
                  >
                    {{discourseTag
                      suggestion.name
                      count=suggestion.count
                      noHref=true
                    }}
                  </DButton>
                </dropdown.item>
              {{/each}}
            </DropdownMenu>
          {{/if}}
        </:content>
      </DMenu>
    {{/if}}
  </template>
}