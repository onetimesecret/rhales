# spec/rhales/core/template_engine_each_block_spec.rb
#
# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe Rhales::TemplateEngine, '{{#each}} block variables' do
  def render(template, client)
    context = Rhales::Context.minimal(client: client)
    Rhales::TemplateEngine.new(template, context).render
  end

  describe '@last' do
    it 'is true only for the final element' do
      template = '{{#each items}}{{this}}={{#if @last}}LAST{{/if}}|{{/each}}'
      output   = render(template, items: %w[a b c])

      expect(output).to eq('a=|b=|c=LAST|')
    end

    it 'enables comma-separated output via {{#unless @last}}' do
      template = '{{#each items}}{{this}}{{#unless @last}},{{/unless}}{{/each}}'
      output   = render(template, items: %w[a b c])

      expect(output).to eq('a,b,c')
    end

    it 'reflects the inner loop in nested {{#each}} blocks' do
      template = '{{#each rows}}[{{#each this}}{{.}}{{#unless @last}}-{{/unless}}{{/each}}]{{/each}}'
      output   = render(template, rows: [%w[a b], %w[c d e]])

      expect(output).to eq('[a-b][c-d-e]')
    end

    it 'is true for the only element in a single-item collection' do
      template = '{{#each items}}{{#if @last}}only{{/if}}{{/each}}'
      output   = render(template, items: ['x'])

      expect(output).to eq('only')
    end

    it 'is false for all elements when none is last (empty collection)' do
      template = 'start{{#each items}}{{#if @last}}!{{/if}}{{/each}}end'
      output   = render(template, items: [])

      expect(output).to eq('startend')
    end
  end

  describe '@first and @index (regression)' do
    it 'still reports @first correctly alongside @last' do
      template = '{{#each items}}{{#if @first}}F{{/if}}{{this}}{{#if @last}}L{{/if}}|{{/each}}'
      output   = render(template, items: %w[a b c])

      expect(output).to eq('Fa|b|cL|')
    end

    it 'still exposes @index' do
      template = '{{#each items}}{{@index}}:{{this}} {{/each}}'
      output   = render(template, items: %w[a b c])

      expect(output).to eq('0:a 1:b 2:c ')
    end
  end
end
